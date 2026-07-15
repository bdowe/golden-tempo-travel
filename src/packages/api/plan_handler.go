package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
	"unicode/utf8"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/google/uuid"

	"travel-route-planner/store"
)

// planMaxIterations bounds the agent tool loop. A rich session (local recs +
// several place searches + flights/events/stays + one create_itinerary) runs
// 8–11 iterations; parallel tool calls share an iteration. Hitting the cap
// ends the stream gracefully instead of letting a pathological loop burn cost.
const planMaxIterations = 15

// planMaxMessages / planMaxMessageChars bound the resent conversation history.
// Every agent-loop iteration (up to planMaxIterations) re-pays input tokens on
// the full history, so these bounds are a hard cost lever. The working limit
// is compaction (plan_compactor.go): histories reaching planCompactThreshold
// are summarized down before the turn runs, and an updated client keeps its
// wire history small by resending the summary instead of the folded messages.
// planMaxMessages is only the backstop above that — old clients that ignore
// the compaction events get re-compacted server-side every turn until this
// cap, so hitting it means a runaway or abusive client. Violations return a
// friendly SSE `error` event, not a 500.
const (
	planMaxMessages     = 60
	planMaxMessageChars = 20000
)

type PlanRequest struct {
	Messages []PlanChatMessage `json:"messages"`
	// Summary is the compacted context from earlier turns, previously handed to
	// the client via the `compacted` SSE event; it stands in for the messages it
	// folded away and precedes Messages as established context.
	Summary string `json:"summary"`
	ChatID  string `json:"chat_id"`
	// TripID binds the session to an existing saved trip: the agent then refines
	// that trip in place (update_itinerary_section) and can never create a new
	// trip version. Requires an authenticated owner.
	TripID string `json:"trip_id"`
}

type PlanChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

func sendSSE(w http.ResponseWriter, eventType string, data any) {
	payload, _ := json.Marshal(map[string]any{"type": eventType, "data": data})
	fmt.Fprintf(w, "data: %s\n\n", payload)
	w.(http.Flusher).Flush()
}

func planHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	if _, ok := w.(http.Flusher); !ok {
		http.Error(w, "streaming not supported", http.StatusInternalServerError)
		return
	}

	var req PlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		sendSSE(w, "error", map[string]string{"message": "invalid request body"})
		return
	}

	// Cap the conversation before any model call: the whole history is resent
	// on every agent-loop iteration, so these bounds are a hard cost lever.
	if len(req.Messages) > planMaxMessages {
		sendSSE(w, "error", map[string]string{"message": "This conversation is too long to continue. Please start a new chat to keep planning."})
		return
	}
	for _, m := range req.Messages {
		if utf8.RuneCountInString(m.Content) > planMaxMessageChars {
			sendSSE(w, "error", map[string]string{"message": "One of the messages is too long for the planner. Please shorten it and try again."})
			return
		}
	}
	if utf8.RuneCountInString(req.Summary) > planMaxMessageChars {
		sendSSE(w, "error", map[string]string{"message": "This conversation is too long to continue. Please start a new chat to keep planning."})
		return
	}

	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		sendSSE(w, "error", map[string]string{"message": "ANTHROPIC_API_KEY not configured"})
		return
	}

	client := newAnthropicClient(apiKey)

	// Resolve the caller once: anonymous sessions get no personalization and no
	// preference-writing tool; signed-in sessions get both.
	uid, authed := userIDFromRequest(r)
	ctx := r.Context()

	// Snapshot the wire history as the client sent it, BEFORE the compaction
	// block below rewrites req.Messages (or prepends the summary-as-message).
	// Session persistence must store what a live client would resend — never
	// the prepended summary message, which would duplicate context on resume.
	rawMessages, rawSummary := req.Messages, req.Summary

	// Compaction must rewrite req.Messages BEFORE the session below captures
	// req by value (the profile distiller reads session.req.Messages). On
	// threshold, fold the older messages into a summary and hand it back to
	// the client (`compacted`), which resends it as req.Summary instead of the
	// folded messages — so each stretch of history is summarized once. A
	// summarizer failure is never surfaced: the turn proceeds on the full
	// (≤ planMaxMessages) history and compaction retries next turn.
	var planCompacted, planCompactFailed bool
	if len(req.Messages) >= planCompactThreshold {
		sendSSE(w, "compacting", map[string]string{})
		cctx, cancel := context.WithTimeout(ctx, compactTimeout)
		newMsgs, summary, through, err := compactPlanMessages(cctx, client, req.Summary, req.Messages)
		cancel()
		if err != nil {
			log.Printf("plan compact: %v", err)
			planCompactFailed = true
			if strings.TrimSpace(req.Summary) != "" {
				req.Messages = append([]PlanChatMessage{summaryAsMessage(req.Summary)}, req.Messages...)
			}
		} else {
			req.Messages = newMsgs
			req.Summary = summary
			planCompacted = true
			sendSSE(w, "compacted", map[string]any{"summary": summary, "through_index": through})
		}
	} else if strings.TrimSpace(req.Summary) != "" {
		req.Messages = append([]PlanChatMessage{summaryAsMessage(req.Summary)}, req.Messages...)
	}

	// session carries the per-request state the tool dispatchers need
	// (plan_tool_registry.go) and the outcomes read back below: the persisted
	// or refined trip id, and whether the profile distiller already fired.
	session := &planSession{
		ctx:    ctx,
		w:      w,
		req:    req,
		client: client,
		authed: authed,
		uid:    uid,
	}

	// Session-level instrumentation for every caller — anonymous sessions
	// carry a null user id, so total AI spend and the authed/anonymous split
	// are both measurable. Completion carries token usage, tool calls, cache
	// hits and cap state. Deferred so it records however the stream ends.
	var planTokensIn, planTokensOut int64
	var planCacheRead, planCacheWrite int64
	var planToolCalls, planIterations int
	var planCapHit bool
	var planUID *uuid.UUID
	if authed {
		planUID = &uid
	}
	// Also runs the free-cap plan_runs crossing check (free_cap.go) — one
	// count query, entirely off the SSE hot path, skipped when unauthed or
	// degraded.
	go recordPlanSessionStart(planUID, authed)
	defer func() {
		recordEventOpt(planUID, "plan_session_completed", session.tripID, map[string]any{
			"authenticated":         authed,
			"input_tokens":          planTokensIn,
			"output_tokens":         planTokensOut,
			"tool_calls":            planToolCalls,
			"iterations":            planIterations,
			"max_iterations_hit":    planCapHit,
			"cache_read_tokens":     planCacheRead,
			"cache_creation_tokens": planCacheWrite,
			"compacted":             planCompacted,
			"compaction_failed":     planCompactFailed,
		})
	}()

	// A trip-bound session must verifiably own the trip before anything streams;
	// failing closed here guarantees a refine panel can never fall back to the
	// version-creating create_itinerary flow.
	var boundTripID *uuid.UUID
	if strings.TrimSpace(req.TripID) != "" {
		tid, err := uuid.Parse(req.TripID)
		if err != nil || !authed {
			sendSSE(w, "error", map[string]string{"message": "sign in to refine this trip"})
			return
		}
		if _, err := store.New(dbPool).GetTripByIDAndOwner(r.Context(), store.GetTripByIDAndOwnerParams{ID: tid, UserID: uid}); err != nil {
			sendSSE(w, "error", map[string]string{"message": "trip not found"})
			return
		}
		boundTripID = &tid
	}
	session.boundTripID = boundTripID

	// Persist the conversation from its very first turn so leaving
	// mid-discussion never loses it (specs/continue-where-you-left-off).
	// Two best-effort writes: a synchronous one now, so the user's message
	// survives even if the stream dies immediately, and a deferred one that
	// appends whatever assistant text streamed — the same text the client
	// commits, on both its success and error paths. When compaction ran this
	// turn, the compacted history + new summary are stored instead of the raw
	// snapshot, matching the client's post-`compacted` wire state. Trip-bound
	// sessions patch a saved trip in place — nothing to resume — and anonymous
	// or degraded sessions stay ephemeral, like anonymous trips.
	persistSession := authed && dbPool != nil &&
		strings.TrimSpace(req.ChatID) != "" && boundTripID == nil
	var turnText strings.Builder
	if persistSession {
		persistMsgs, persistSummary := rawMessages, rawSummary
		if planCompacted {
			// compactPlanMessages returns [summary-as-message, ...kept tail];
			// the client's post-`compacted` wire state is the tail alone, with
			// the summary carried separately — store it the same way.
			persistMsgs, persistSummary = req.Messages[1:], req.Summary
		}
		savePlanChatSession(ctx, uid, req.ChatID, persistSummary, persistMsgs)
		defer func() {
			msgs := persistMsgs
			if t := turnText.String(); t != "" {
				msgs = append(append([]PlanChatMessage{}, persistMsgs...),
					PlanChatMessage{Role: "assistant", Content: t})
			}
			// The request context is gone once the handler returns.
			dctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			savePlanChatSession(dctx, uid, req.ChatID, persistSummary, msgs)
		}()
	}

	// The tool table (plan_tool_registry.go) is the single source of truth for
	// what the agent can do: the tools slice sent to the API is generated from
	// it in registry order (order-stable — the tools array is part of the
	// prompt-cache prefix that the system-prompt cache breakpoint covers), and
	// tool_use blocks dispatch through it below. Trip-bound sessions get the
	// in-place section tool instead of create_itinerary, so a refinement can
	// never spawn a new trip version; personalization tools are signed-in only.
	tools := planSessionTools(session)

	var messages []anthropic.MessageParam
	for _, m := range req.Messages {
		if m.Role == "user" {
			messages = append(messages, anthropic.NewUserMessage(anthropic.NewTextBlock(m.Content)))
		} else {
			messages = append(messages, anthropic.NewAssistantMessage(anthropic.NewTextBlock(m.Content)))
		}
	}

	today := time.Now()
	basePrompt := "You are an expert travel agent. Today's date is " + today.Format("Monday, January 2, 2006") + " (" + today.Format("2006-01-02") + "). When a traveler gives a date without a year, assume the soonest upcoming occurrence on or after today — never a past year. Use dates in YYYY-MM-DD form when calling tools. Help users plan trips by searching for specific places and attractions. For each city, ALWAYS call search_local_recommendations FIRST — these are hand-curated picks from real locals, the legit info you can't get by googling. Prefer them over generic results, build the itinerary around them where they fit the traveler, and cite the local by name in your reply (e.g. 'Ana, a Lisbon chef, swears by…'). When a local pick becomes an itinerary place, carry its id into local_recommendation_id and its source_name into local_source_name. Then use search_places to fill gaps and find any other real locations with coordinates. Search for individual places (e.g. 'Louvre Museum Paris') rather than broad queries. Include a mix of activities/attractions and dining (restaurants), guided by the traveler's interests, budget, and pace. When you call create_itinerary, tag each location with category ('attraction' or 'restaurant'), a time_of_day ('morning', 'afternoon', or 'evening'), and a day (the 1-based trip day it falls on, increasing chronologically across the whole trip) so each day reads as a sensible schedule. When you have gathered enough places for the user's trip, call create_itinerary to finalize the plan; pass start_date (and end_date) whenever the traveler has given or agreed to travel dates, with day 1 being the start date. You can also use search_flights to find real flight options — ask for the traveler's departure city/airport and dates if you don't know them, and pick optimize_for from their budget (budget→cost, luxury→time, otherwise balanced); summarize the top 2-3 options in your own words and help them choose — do not tell the traveler to look at cards or lists in the chat. For travel between Greek islands, use suggest_ferries (ferries are the primary way to island-hop); note that in Greece search_events returns curated source links rather than ticketed listings. Use get_weather when weather changes the advice — packing, outdoor days, beach or ski viability, seasonal closures; for far-off dates it returns last year's weather as a seasonal guide, so present it as 'typically', never as a forecast. For signed-in travelers: when they reference a trip you've already planned together, call get_trip to read what's saved instead of asking them to repeat it; and when you give time-sensitive booking advice about a saved trip (book the ferry, reserve that restaurant), call add_booking_todo so it lands on their checklist instead of getting lost in chat. Be conversational and helpful — ask clarifying questions if needed before searching. Format replies with light markdown — short paragraphs, **bold** for place names, hyphen lists — no headings or tables."

	// Fold the signed-in traveler's saved preferences into the system prompt.
	// The profile-keeping instruction applies even before any row exists, so
	// the first durable fact a traveler reveals gets captured.
	systemPrompt := basePrompt
	if authed {
		if prefs, err := store.New(dbPool).GetPreferences(ctx, uid); err == nil {
			systemPrompt = personalizedSystemPrompt(basePrompt, &prefs)
		}
		systemPrompt += profileNotesInstruction
	}
	if boundTripID != nil {
		systemPrompt += "\n\nYou are refining an existing saved trip in place. The conversation's first message describes the current itinerary and which section the traveler wants to change. Apply changes by calling update_itinerary_section with the targeted scope and the COMPLETE updated list of places for that section — include unchanged places with their existing coordinates, city, day, time_of_day and category tags so they aren't lost. Use search_places to find real coordinates for any new place before adding it. Only change the section the traveler asked about unless they broaden the request."
	}

	// prevCacheMarker tracks the conversation cache breakpoint set on the
	// newest tool-results message; it must be cleared before setting the next
	// one (the API allows at most 4 breakpoints per request).
	var prevCacheMarker *anthropic.CacheControlEphemeralParam

	for {
		planIterations++
		if planIterations > planMaxIterations {
			planCapHit = true
			sendSSE(w, "error", map[string]string{"message": "This planning session hit its step limit. Send another message to continue from where we left off."})
			return
		}

		params := anthropic.MessageNewParams{
			Model:     anthropic.ModelClaudeSonnet4_6,
			MaxTokens: 8192,
			System: []anthropic.TextBlockParam{
				{
					Text:         systemPrompt,
					CacheControl: anthropic.NewCacheControlEphemeralParam(),
				},
			},
			Tools:    tools,
			Messages: messages,
		}

		stream := client.Messages.NewStreaming(ctx, params)
		resp := anthropic.Message{}

		for stream.Next() {
			event := stream.Current()
			resp.Accumulate(event)

			if ev, ok := event.AsAny().(anthropic.ContentBlockDeltaEvent); ok {
				if delta, ok := ev.Delta.AsAny().(anthropic.TextDelta); ok {
					turnText.WriteString(delta.Text)
					sendSSE(w, "text_delta", map[string]string{"text": delta.Text})
				}
			}
		}
		if err := stream.Err(); err != nil {
			sendSSE(w, "error", map[string]string{"message": err.Error()})
			return
		}
		planTokensIn += resp.Usage.InputTokens
		planTokensOut += resp.Usage.OutputTokens
		planCacheRead += resp.Usage.CacheReadInputTokens
		planCacheWrite += resp.Usage.CacheCreationInputTokens

		// A max_tokens stop mid-tool-call means truncated tool input JSON —
		// previously this failed silently and produced an empty itinerary.
		// Surface it instead of continuing with garbage.
		if resp.StopReason == anthropic.StopReasonMaxTokens {
			sendSSE(w, "error", map[string]string{"message": "The response was cut off before it finished. Try asking for a shorter plan or fewer places at once."})
			return
		}
		if resp.StopReason != anthropic.StopReasonToolUse {
			break
		}

		messages = append(messages, resp.ToParam())
		var toolResults []anthropic.ContentBlockParamUnion

		for _, block := range resp.Content {
			variant, ok := block.AsAny().(anthropic.ToolUseBlock)
			if !ok {
				continue
			}
			sendSSE(w, "tool_call", map[string]string{"name": variant.Name})
			planToolCalls++

			entry := planToolByName[variant.Name]
			if entry == nil {
				// Matches the old switch's no-case fallthrough: an unknown tool
				// name gets no result block (the API only calls defined tools).
				continue
			}
			result, isErr := entry.run(session, variant.Input)
			if !entry.noResultEvent {
				sendSSE(w, "tool_result", map[string]string{"name": variant.Name})
			}
			toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, result, isErr))
		}

		messages = append(messages, anthropic.NewUserMessage(toolResults...))

		// Move the conversation cache breakpoint onto the newest tool-results
		// message so each iteration re-reads the growing history from cache
		// instead of paying full input cost for it. The system-prompt
		// breakpoint (above) covers tools + system; this one covers the turn
		// transcript.
		if prevCacheMarker != nil {
			*prevCacheMarker = anthropic.CacheControlEphemeralParam{}
			prevCacheMarker = nil
		}
		if blocks := messages[len(messages)-1].Content; len(blocks) > 0 {
			if cc := blocks[len(blocks)-1].GetCacheControl(); cc != nil {
				*cc = anthropic.NewCacheControlEphemeralParam()
				prevCacheMarker = cc
			}
		}

		select {
		case <-ctx.Done():
			return
		default:
		}
	}
}

// resolveIATA turns a city name or IATA code into an IATA code for flight
// search. A 3-letter alphabetic input is treated as a code; anything else is
// looked up via Duffel, preferring a city (metropolitan) code so the search
// spans all of a city's airports. Returns "" when nothing resolves.
func resolveIATA(ctx context.Context, s string) string {
	s = strings.TrimSpace(s)
	if len(s) == 3 && isAlpha(s) {
		return strings.ToUpper(s)
	}
	results, err := duffelService.SearchAirports(ctx, s)
	if err != nil || len(results) == 0 {
		return ""
	}
	for _, a := range results {
		if a.SubType == "city" && a.IataCode != "" {
			return a.IataCode
		}
	}
	return results[0].IataCode
}

func isAlpha(s string) bool {
	for _, r := range s {
		if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')) {
			return false
		}
	}
	return s != ""
}

// summarizeOffers builds a compact text summary of ranked offers for the model,
// so it can describe and compare them without re-sending the full payload (the
// UI already received it via the "flights" event, shown as a summary chip).
func summarizeOffers(origin, dest string, offers []FlightOffer) string {
	if len(offers) == 0 {
		return fmt.Sprintf("No flights found from %s to %s for those dates.", origin, dest)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Found %d ranked flight options %s→%s (best first):\n", len(offers), origin, dest)
	for i, o := range offers {
		airline := "—"
		if len(o.Airlines) > 0 {
			airline = strings.Join(o.Airlines, "/")
		}
		stops := "nonstop"
		if o.Stops == 1 {
			stops = "1 stop"
		} else if o.Stops > 1 {
			stops = fmt.Sprintf("%d stops", o.Stops)
		}
		fmt.Fprintf(&b, "%d. %s — %s %.0f, %s, %dh%02dm (score %.1f)\n",
			i+1, airline, o.Currency, o.Price, stops, o.DurationMin/60, o.DurationMin%60, o.Score)
	}
	b.WriteString("Summarize the top 2-3 options in your own words and help the traveler choose; the full ranked list is saved with their trip.")
	return b.String()
}

// summarizeEvents renders the events returned for a city into a compact text
// block for the model (the events themselves are streamed to the UI, shown as
// a summary chip).
func summarizeEvents(city string, events []Event) string {
	if len(events) == 0 {
		return fmt.Sprintf("No events found in %s for those dates.", city)
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Found %d events in %s (soonest first):\n", len(events), city)
	for i, e := range events {
		when := e.StartDate
		if e.StartTime != "" {
			when += " " + e.StartTime
		}
		line := fmt.Sprintf("%d. %s — %s", i+1, e.Name, when)
		if e.Venue != "" {
			line += " @ " + e.Venue
		}
		if e.Category != "" {
			line += " (" + e.Category + ")"
		}
		b.WriteString(line + "\n")
	}
	b.WriteString("In your reply, highlight the events that fit the traveler's interests and dates; the full list is saved with their trip.")
	return b.String()
}

// profileNotesInstruction is the standing profile-keeping rule appended to every
// authenticated session's system prompt, whether or not notes exist yet.
const profileNotesInstruction = "\n\nWhen you learn something durable about this traveler — travel companions, dietary needs, accommodation style, accessibility needs, likes or dislikes — call save_preferences with profile_notes set to the COMPLETE updated profile: your current notes merged with the new fact, de-duplicated, as short bullet lines (max ~15). Never send only the new fact. Don't store one-off trip details or sensitive information (health, religion, politics) unless the traveler explicitly asks you to remember it."

// personalizedSystemPrompt appends the traveler's saved preferences and
// AI-maintained profile notes to the base prompt, omitting any fields that are
// unset. Returns base unchanged when there is nothing to add.
func personalizedSystemPrompt(base string, p *store.TravelerPreference) string {
	if p == nil {
		return base
	}
	var parts []string
	if p.Budget != nil && *p.Budget != "" {
		parts = append(parts, "budget: "+*p.Budget)
	}
	if p.Pace != nil && *p.Pace != "" {
		parts = append(parts, "pace: "+*p.Pace)
	}
	if len(p.Interests) > 0 {
		parts = append(parts, "interests: "+strings.Join(p.Interests, ", "))
	}
	var homeNote string
	if p.HomeAirport != nil && *p.HomeAirport != "" {
		parts = append(parts, "home airport: "+*p.HomeAirport)
		homeNote = " When searching flights, default the origin to the traveler's home airport (" +
			*p.HomeAirport + ") and state the assumption (e.g. 'flying from " + *p.HomeAirport +
			"'); only use a different origin if the trip clearly starts elsewhere or they say so."
	}
	out := base
	if len(parts) > 0 {
		out += "\n\nTraveler preferences — " + strings.Join(parts, "; ") +
			". Tailor your suggestions accordingly." + homeNote
	}
	if p.ProfileNotes != nil && strings.TrimSpace(*p.ProfileNotes) != "" {
		out += "\n\nTraveler profile notes (maintained by you):\n" + strings.TrimSpace(*p.ProfileNotes)
	}
	return out
}

// notesPreview returns a short excerpt of saved notes for the profile_updated
// SSE event; empty when no notes were part of the save.
func notesPreview(notes *string) string {
	if notes == nil {
		return ""
	}
	r := []rune(strings.TrimSpace(*notes))
	if len(r) > 80 {
		return string(r[:80]) + "…"
	}
	return string(r)
}
