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
// the full history, so an unbounded history multiplies token cost by up to
// 15x. Both caps sit far above anything the Flutter chat UI produces (a few
// dozen short turns, plus one long itinerary-context first message on refine);
// hitting them means a runaway or abusive client. Violations return a friendly
// SSE `error` event, not a 500.
const (
	planMaxMessages     = 40
	planMaxMessageChars = 20000
)

type PlanRequest struct {
	Messages []PlanChatMessage `json:"messages"`
	ChatID   string            `json:"chat_id"`
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

	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		sendSSE(w, "error", map[string]string{"message": "ANTHROPIC_API_KEY not configured"})
		return
	}

	client := newAnthropicClient(apiKey)

	// Resolve the caller once: anonymous sessions get no personalization and no
	// preference-writing tool; signed-in sessions get both.
	uid, authed := userIDFromRequest(r)

	// Session-level instrumentation for every caller — anonymous sessions
	// carry a null user id, so total AI spend and the authed/anonymous split
	// are both measurable. Completion carries token usage, tool calls, cache
	// hits and cap state. Deferred so it records however the stream ends.
	var planTokensIn, planTokensOut int64
	var planCacheRead, planCacheWrite int64
	var planToolCalls, planIterations int
	var planCapHit bool
	var planTripID *uuid.UUID
	var planUID *uuid.UUID
	if authed {
		planUID = &uid
	}
	// Also runs the free-cap plan_runs crossing check (free_cap.go) — one
	// count query, entirely off the SSE hot path, skipped when unauthed or
	// degraded.
	go recordPlanSessionStart(planUID, authed)
	defer func() {
		recordEventOpt(planUID, "plan_session_completed", planTripID, map[string]any{
			"authenticated":         authed,
			"input_tokens":          planTokensIn,
			"output_tokens":         planTokensOut,
			"tool_calls":            planToolCalls,
			"iterations":            planIterations,
			"max_iterations_hit":    planCapHit,
			"cache_read_tokens":     planCacheRead,
			"cache_creation_tokens": planCacheWrite,
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

	searchTool := anthropic.ToolParam{
		Name:        "search_places",
		Description: anthropic.String("Search for travel destinations, attractions, restaurants, or points of interest by name or description."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"query": map[string]any{
					"type":        "string",
					"description": "Search query, e.g. 'Eiffel Tower Paris' or 'best museums in Rome'",
				},
			},
			Required: []string{"query"},
		},
	}
	createTool := anthropic.ToolParam{
		Name:        "create_itinerary",
		Description: anthropic.String("Finalize the itinerary with the chosen list of locations to visit. Call this when you have identified all the places for the trip."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"locations": map[string]any{
					"type":        "array",
					"description": "Ordered list of locations to visit",
					"items":       itineraryLocationSchema,
				},
				"title": map[string]any{
					"type":        "string",
					"description": "A short, human-friendly trip name, 3–6 words (e.g. 'Luxury Paris Weekend'). Distinct from the longer summary.",
				},
				"summary": map[string]any{
					"type":        "string",
					"description": "A 1–2 sentence overview of the trip to show the user (the per-day breakdown already appears in the itinerary list, so keep this brief).",
				},
				"start_date": map[string]any{
					"type":        "string",
					"description": "The trip's first day as YYYY-MM-DD (day 1). Include it whenever the traveler has given or agreed to travel dates.",
				},
				"end_date": map[string]any{
					"type":        "string",
					"description": "The trip's last day as YYYY-MM-DD. Optional — if omitted it's derived from start_date plus the number of days in the itinerary.",
				},
			},
			Required: []string{"locations"},
		},
	}
	savePrefsTool := anthropic.ToolParam{
		Name:        "save_preferences",
		Description: anthropic.String("Save what you learn about the traveler so future trips are personalized. Call this when the user reveals a budget level, trip pace, interests, which airport they fly from, or any other durable fact about how they travel. Only include fields you actually learned."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"budget": map[string]any{
					"type":        "string",
					"enum":        []string{"budget", "mid", "luxury"},
					"description": "Overall spending level",
				},
				"pace": map[string]any{
					"type":        "string",
					"enum":        []string{"relaxed", "balanced", "packed"},
					"description": "How packed the days should be",
				},
				"interests": map[string]any{
					"type":        "array",
					"items":       map[string]any{"type": "string"},
					"description": "Theme tags, e.g. museums, food, nightlife, nature",
				},
				"home_airport": map[string]any{
					"type":        "string",
					"description": "The traveler's home/departure airport as an IATA code, e.g. BOS — save it when they mention where they usually fly from",
				},
				"profile_notes": map[string]any{
					"type":        "string",
					"description": "The COMPLETE updated traveler profile as short bullet lines — your current notes (shown in the system prompt) merged with the new fact, de-duplicated, max ~15 lines. Never send only the new fact; always send the full rewritten profile.",
				},
			},
		},
	}

	suggestStaysTool := anthropic.ToolParam{
		Name:        "suggest_stays",
		Description: anthropic.String("Give the traveler links to browse accommodations on Airbnb and Booking.com for a destination. Call this when they want lodging suggestions."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"destination": map[string]any{"type": "string", "description": "City or area, e.g. 'Paris'"},
				"check_in":    map[string]any{"type": "string", "description": "Optional YYYY-MM-DD"},
				"check_out":   map[string]any{"type": "string", "description": "Optional YYYY-MM-DD"},
				"guests":      map[string]any{"type": "integer", "description": "Optional number of guests"},
			},
			Required: []string{"destination"},
		},
	}

	suggestTransportTool := anthropic.ToolParam{
		Name:        "suggest_transport",
		Description: anthropic.String("Give the traveler links to browse transport options. Call this when they need to get to or between destinations. Mode 'flight' returns Google Flights + Kayak; mode 'ground' returns Rome2Rio (covers trains, buses, cars, ferries). For travel between Greek islands, prefer suggest_ferries instead."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"mode":        map[string]any{"type": "string", "enum": []string{"flight", "ground"}, "description": "flight or ground (multimodal)"},
				"origin":      map[string]any{"type": "string", "description": "Origin city or airport, e.g. 'NYC' or 'Paris'"},
				"destination": map[string]any{"type": "string", "description": "Destination city or airport"},
				"depart_date": map[string]any{"type": "string", "description": "Optional YYYY-MM-DD"},
				"return_date": map[string]any{"type": "string", "description": "Optional YYYY-MM-DD (flights only)"},
				"passengers":  map[string]any{"type": "integer", "description": "Optional passenger count"},
			},
			Required: []string{"mode", "origin", "destination"},
		},
	}

	suggestFerriesTool := anthropic.ToolParam{
		Name:        "suggest_ferries",
		Description: anthropic.String("Give the traveler a ferry booking link for a route between two ports/islands — use this for Greek island-hopping (e.g. Santorini→Naxos) and other ferry legs. Backed by Ferryhopper, which aggregates the major Greek operators (Blue Star, SeaJets, etc.)."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"origin":      map[string]any{"type": "string", "description": "Departure port or island, e.g. 'Santorini' or 'Piraeus'"},
				"destination": map[string]any{"type": "string", "description": "Arrival port or island, e.g. 'Naxos'"},
				"date":        map[string]any{"type": "string", "description": "Optional YYYY-MM-DD travel date"},
				"passengers":  map[string]any{"type": "integer", "description": "Optional passenger count"},
			},
			Required: []string{"origin", "destination"},
		},
	}

	searchFlightsTool := anthropic.ToolParam{
		Name: "search_flights",
		Description: anthropic.String("Search real flight options between two places for given dates and present a few good ones (ranked by overall desirability). " +
			"Ask the traveler for their departure city/airport and travel dates first if you don't know them. " +
			"origin/destination may be city names or IATA codes. Choose optimize_for from the traveler's budget: budget→'cost', luxury→'time', otherwise 'balanced'."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"origin":       map[string]any{"type": "string", "description": "Departure city or IATA code, e.g. 'Boston' or 'BOS'"},
				"destination":  map[string]any{"type": "string", "description": "Arrival city or IATA code"},
				"depart_date":  map[string]any{"type": "string", "description": "YYYY-MM-DD"},
				"return_date":  map[string]any{"type": "string", "description": "Optional YYYY-MM-DD for round trips"},
				"adults":       map[string]any{"type": "integer", "description": "Optional, defaults to 1"},
				"child_ages":   map[string]any{"type": "array", "items": map[string]any{"type": "integer"}, "description": "Optional ages of child travelers (one per child, 0-17) — include when the traveler mentions kids"},
				"cabin_class":  map[string]any{"type": "string", "enum": []string{"economy", "premium_economy", "business", "first"}, "description": "Optional cabin, defaults to economy — set when the traveler asks for a specific class"},
				"optimize_for": map[string]any{"type": "string", "enum": []string{"cost", "time", "balanced"}, "description": "Ranking emphasis"},
			},
			Required: []string{"origin", "destination", "depart_date"},
		},
	}

	searchEventsTool := anthropic.ToolParam{
		Name: "search_events",
		Description: anthropic.String("Find local events (concerts, sports, festivals, theatre/shows) happening in a city during specific dates, so the itinerary can account for what's on while the traveler is there. " +
			"Use the city and the dates the traveler is in that city; you already know the trip's cities and dates from the itinerary. " +
			"Present a few that fit the traveler's interests."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"city":       map[string]any{"type": "string", "description": "City name, e.g. 'Paris'"},
				"start_date": map[string]any{"type": "string", "description": "First day to look from, YYYY-MM-DD (when the traveler arrives in the city)"},
				"end_date":   map[string]any{"type": "string", "description": "Last day to look through, YYYY-MM-DD (when the traveler leaves the city)"},
				"category":   map[string]any{"type": "string", "enum": []string{"music", "sports", "arts", "film", "miscellaneous"}, "description": "Optional event category filter"},
			},
			Required: []string{"city", "start_date", "end_date"},
		},
	}

	searchLocalRecsTool := anthropic.ToolParam{
		Name: "search_local_recommendations",
		Description: anthropic.String("Find hand-curated recommendations from real locals for a city — vetted spots you can't get by googling. " +
			"ALWAYS call this FIRST for each city, before search_places. Prefer these picks over generic search results, and when you use one, cite the local by name in your reply (their name is in 'source_name'). " +
			"When you pass a local pick into create_itinerary, copy its 'id' into local_recommendation_id and its 'source_name' into local_source_name so the saved trip credits them."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"city":     map[string]any{"type": "string", "description": "City name, e.g. 'Lisbon'"},
				"category": map[string]any{"type": "string", "enum": []string{"attraction", "restaurant"}, "description": "Optional filter to only sights or only places to eat"},
			},
			Required: []string{"city"},
		},
	}

	updateSectionTool := anthropic.ToolParam{
		Name:        "update_itinerary_section",
		Description: anthropic.String("Replace one section of the traveler's saved itinerary in place. Pass the COMPLETE updated list of places for the targeted section, in visit order — places you omit are removed from that section. Places outside the section are untouched. Use scope 'day' for a single trip day, 'city' for one city/hub and its day trips, or 'trip' for the whole itinerary."),
		InputSchema: anthropic.ToolInputSchemaParam{
			Properties: map[string]any{
				"scope": map[string]any{
					"type":        "string",
					"enum":        []string{"day", "city", "trip"},
					"description": "Which slice of the itinerary to replace.",
				},
				"day": map[string]any{
					"type":        "integer",
					"description": "Required when scope is 'day': the 1-based trip day being replaced.",
				},
				"city": map[string]any{
					"type":        "string",
					"description": "Required when scope is 'city' (the hub city whose items are replaced); optional with scope 'day' to disambiguate when day numbers repeat across cities.",
				},
				"items": map[string]any{
					"type":        "array",
					"description": "The full replacement list for the section, in visit order. Include unchanged places with their existing coordinates and tags so they aren't lost.",
					"items":       itineraryLocationSchema,
				},
			},
			Required: []string{"scope", "items"},
		},
	}

	tools := []anthropic.ToolUnionParam{
		{OfTool: &searchTool},
		{OfTool: &suggestStaysTool},
		{OfTool: &suggestTransportTool},
		{OfTool: &suggestFerriesTool},
		{OfTool: &searchFlightsTool},
		{OfTool: &searchEventsTool},
		{OfTool: &searchLocalRecsTool},
		{OfTool: &getWeatherTool},
	}
	// Trip-bound sessions get the in-place section tool instead of
	// create_itinerary, so a refinement can never spawn a new trip version.
	if boundTripID != nil {
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &updateSectionTool})
	} else {
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &createTool})
	}
	if authed {
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &savePrefsTool})
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &getTripTool})
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &addBookingTodoTool})
	}

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

	ctx := r.Context()
	distilled := false

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

			switch variant.Name {
			case "search_places":
				var in struct {
					Query string `json:"query"`
				}
				json.Unmarshal(variant.Input, &in)

				results, err := placesService.SearchPlaces(in.Query)
				var resultStr string
				if err != nil {
					resultStr = fmt.Sprintf("Error searching places: %v", err)
				} else {
					b, _ := json.Marshal(results)
					resultStr = string(b)
				}
				sendSSE(w, "tool_result", map[string]string{"name": "search_places"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, resultStr, err != nil))

			case "create_itinerary":
				var in struct {
					Locations []map[string]any `json:"locations"`
					Title     string           `json:"title"`
					Summary   string           `json:"summary"`
					StartDate string           `json:"start_date"`
					EndDate   string           `json:"end_date"`
				}
				json.Unmarshal(variant.Input, &in)

				// Distance-optimize the walking order within each day/time-of-day
				// block, leaving Claude's day and time-of-day assignments intact.
				in.Locations = reorderItineraryByDistance(in.Locations)

				donePayload := map[string]any{"locations": in.Locations, "summary": in.Summary}
				// Persist the trip only for signed-in callers; anonymous sessions
				// stay ephemeral (no trip_id in the done event).
				if authed {
					if tripID, err := persistTrip(ctx, uid, req.ChatID, in.Title, in.Summary, in.StartDate, in.EndDate, in.Locations); err != nil {
						log.Printf("failed to persist trip: %v", err)
					} else {
						donePayload["trip_id"] = tripID
						if parsed, err := uuid.Parse(tripID); err == nil {
							planTripID = &parsed
							go recordEvent(uid, "trip_created", &parsed, map[string]any{
								"item_count": len(in.Locations),
							})
							// Free-cap active_trips crossing signal — a new
							// lineage may take the user past the cap; new
							// versions of an existing lineage never do.
							go recordActiveTripsCapSignal(uid, parsed)
						}
						// Distill what this conversation revealed about the traveler
						// in the background — it must never delay or fail the trip.
						// context.Background(): the request ctx dies with the handler.
						if !distilled {
							distilled = true
							go distillTravelerProfile(context.Background(), client, uid, req.Messages)
						}
					}
				}
				sendSSE(w, "done", donePayload)
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, "Itinerary created successfully.", false))

			case "update_itinerary_section":
				var in struct {
					Scope string           `json:"scope"`
					Day   *int             `json:"day"`
					City  string           `json:"city"`
					Items []map[string]any `json:"items"`
				}
				json.Unmarshal(variant.Input, &in)

				msg := "Section updated — the traveler's trip page has refreshed."
				var err error
				if boundTripID == nil {
					err = fmt.Errorf("no trip is bound to this session")
					msg = "This session is not bound to a saved trip; update_itinerary_section is unavailable."
				} else {
					// Same in-block walking-distance cleanup create_itinerary gets.
					in.Items = reorderItineraryByDistance(in.Items)
					if err = replaceTripSection(ctx, *boundTripID, sectionSelector{Scope: in.Scope, Day: in.Day, City: in.City}, in.Items); err != nil {
						msg = fmt.Sprintf("Could not update the section: %v", err)
					} else {
						sendSSE(w, "trip_updated", map[string]string{"trip_id": boundTripID.String()})
						planTripID = boundTripID
						go recordEvent(uid, "trip_refined", boundTripID, map[string]any{
							"scope": in.Scope,
						})
					}
				}
				sendSSE(w, "tool_result", map[string]string{"name": "update_itinerary_section"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, msg, err != nil))

			case "save_preferences":
				var in struct {
					Budget       *string  `json:"budget"`
					Pace         *string  `json:"pace"`
					Interests    []string `json:"interests"`
					HomeAirport  *string  `json:"home_airport"`
					ProfileNotes *string  `json:"profile_notes"`
				}
				json.Unmarshal(variant.Input, &in)

				budget, _ := normalizeChoice(in.Budget, allowedBudgets, "budget")
				pace, _ := normalizeChoice(in.Pace, allowedPaces, "pace")
				homeAirport, _ := normalizeAirportCode(in.HomeAirport)
				var interestsArg interface{}
				if in.Interests != nil {
					interestsArg = normalizeInterests(in.Interests)
				}
				notes := normalizeNotes(in.ProfileNotes)
				if notes != nil && *notes == "" {
					// The agent can never wipe notes; only the user (PUT) can clear.
					notes = nil
				}
				_, err := store.New(dbPool).UpsertPreferences(ctx, store.UpsertPreferencesParams{
					UserID: uid, Budget: budget, Pace: pace, Interests: interestsArg, HomeAirport: homeAirport, ProfileNotes: notes,
				})
				msg := "Preferences saved."
				if err != nil {
					msg = fmt.Sprintf("Could not save preferences: %v", err)
				} else {
					var changed []string
					if budget != nil {
						changed = append(changed, "budget")
					}
					if pace != nil {
						changed = append(changed, "pace")
					}
					if interestsArg != nil {
						changed = append(changed, "interests")
					}
					if homeAirport != nil {
						changed = append(changed, "home_airport")
					}
					if notes != nil {
						changed = append(changed, "profile_notes")
					}
					if len(changed) > 0 {
						sendSSE(w, "profile_updated", map[string]any{
							"fields": changed, "notes_preview": notesPreview(notes),
						})
					}
				}
				sendSSE(w, "tool_result", map[string]string{"name": "save_preferences"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, msg, err != nil))

			case "suggest_stays":
				var in struct {
					Destination string `json:"destination"`
					CheckIn     string `json:"check_in"`
					CheckOut    string `json:"check_out"`
					Guests      int    `json:"guests"`
				}
				json.Unmarshal(variant.Input, &in)
				links := providerLinks(AccommodationQuery{
					Destination: in.Destination, CheckIn: in.CheckIn, CheckOut: in.CheckOut, Guests: in.Guests,
				})
				sendSSE(w, "stays", map[string]any{"destination": in.Destination, "links": links})
				sendSSE(w, "tool_result", map[string]string{"name": "suggest_stays"})
				b, _ := json.Marshal(links)
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, "Provided browse links: "+string(b), false))

			case "suggest_transport":
				var in struct {
					Mode        string `json:"mode"`
					Origin      string `json:"origin"`
					Destination string `json:"destination"`
					DepartDate  string `json:"depart_date"`
					ReturnDate  string `json:"return_date"`
					Passengers  int    `json:"passengers"`
				}
				json.Unmarshal(variant.Input, &in)
				links := transportLinks(TransportQuery{
					Mode: in.Mode, Origin: in.Origin, Destination: in.Destination,
					DepartDate: in.DepartDate, ReturnDate: in.ReturnDate, Passengers: in.Passengers,
				})
				sendSSE(w, "transport", map[string]any{
					"mode": in.Mode, "origin": in.Origin, "destination": in.Destination, "links": links,
				})
				sendSSE(w, "tool_result", map[string]string{"name": "suggest_transport"})
				b, _ := json.Marshal(links)
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, "Provided browse links: "+string(b), false))

			case "suggest_ferries":
				var in struct {
					Origin      string `json:"origin"`
					Destination string `json:"destination"`
					Date        string `json:"date"`
					Passengers  int    `json:"passengers"`
				}
				json.Unmarshal(variant.Input, &in)
				options := ferryService.SearchFerries(FerryQuery{
					Origin: in.Origin, Destination: in.Destination,
					Date: in.Date, Passengers: in.Passengers,
				})
				sendSSE(w, "ferries", map[string]any{
					"origin": in.Origin, "destination": in.Destination, "options": options,
				})
				sendSSE(w, "tool_result", map[string]string{"name": "suggest_ferries"})
				b, _ := json.Marshal(options)
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, "Provided ferry booking link(s): "+string(b), false))

			case "search_flights":
				var in struct {
					Origin      string `json:"origin"`
					Destination string `json:"destination"`
					DepartDate  string `json:"depart_date"`
					ReturnDate  string `json:"return_date"`
					Adults      int    `json:"adults"`
					ChildAges   []int  `json:"child_ages"`
					CabinClass  string `json:"cabin_class"`
					OptimizeFor string `json:"optimize_for"`
				}
				json.Unmarshal(variant.Input, &in)

				originIata := resolveIATA(ctx, in.Origin)
				destIata := resolveIATA(ctx, in.Destination)
				if originIata == "" || destIata == "" {
					sendSSE(w, "tool_result", map[string]string{"name": "search_flights"})
					msg := fmt.Sprintf("Could not resolve %q or %q to an airport. Ask the traveler to clarify the city or airport.", in.Origin, in.Destination)
					toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, msg, true))
					break
				}

				adults := in.Adults
				if adults < 1 {
					adults = 1
				}
				offers, err := duffelService.SearchFlightOffers(ctx, FlightSearchRequest{
					Origin: originIata, Destination: destIata, DepartDate: in.DepartDate,
					ReturnDate: in.ReturnDate, Adults: adults, ChildAges: in.ChildAges,
					CabinClass: in.CabinClass, OptimizeFor: in.OptimizeFor,
				})
				if err != nil {
					sendSSE(w, "tool_result", map[string]string{"name": "search_flights"})
					toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, fmt.Sprintf("Error searching flights: %v", err), true))
					break
				}

				bestN := RankFlightOffers(offers, in.OptimizeFor)
				if len(bestN) > 4 {
					bestN = bestN[:4]
				}
				attachBookingURLs(bestN, FlightSearchRequest{
					Origin: originIata, Destination: destIata,
					DepartDate: in.DepartDate, ReturnDate: in.ReturnDate, Adults: adults,
				})
				if len(bestN) > 0 {
					sendSSE(w, "flights", map[string]any{
						"origin": originIata, "destination": destIata,
						"depart_date": in.DepartDate, "optimize_for": normalizeOptimizeFor(in.OptimizeFor),
						"offers": bestN,
					})
				}
				sendSSE(w, "tool_result", map[string]string{"name": "search_flights"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, summarizeOffers(originIata, destIata, bestN), false))

			case "search_events":
				var in struct {
					City      string  `json:"city"`
					StartDate string  `json:"start_date"`
					EndDate   string  `json:"end_date"`
					Category  *string `json:"category"`
				}
				json.Unmarshal(variant.Input, &in)

				events, err := eventsService.SearchEvents(ctx, in.City, in.StartDate, in.EndDate, in.Category)
				if len(events) > 0 {
					sendSSE(w, "events", map[string]any{
						"city":       in.City,
						"start_date": in.StartDate,
						"end_date":   in.EndDate,
						"events":     events,
					})
				}

				// Greece has no usable events API, so when the structured lookup
				// comes back empty (or errors, e.g. no key) for a Greek city, fall
				// back to curated Greek source links instead of nothing.
				summary := summarizeEvents(in.City, events)
				if len(events) == 0 && isGreekLocation(in.City) {
					links := greekEventLinks(in.City, in.StartDate, in.EndDate)
					sendSSE(w, "event_links", map[string]any{"city": in.City, "links": links})
					b, _ := json.Marshal(links)
					summary = "No ticketed listings via the events provider for " + in.City +
						". Provided Greek event-discovery links: " + string(b)
				} else if err != nil {
					summary = fmt.Sprintf("Error searching events: %v", err)
				}

				sendSSE(w, "tool_result", map[string]string{"name": "search_events"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, summary, err != nil && len(events) == 0 && !isGreekLocation(in.City)))

			case "search_local_recommendations":
				var in struct {
					City     string `json:"city"`
					Category string `json:"category"`
				}
				json.Unmarshal(variant.Input, &in)

				recs, err := localRecsService.SearchByCity(ctx, in.City, in.Category)
				if len(recs) > 0 {
					sendSSE(w, "local_recs", map[string]any{"city": in.City, "recommendations": recs})
				}
				summary := summarizeLocalRecs(in.City, recs)
				if err != nil {
					summary = fmt.Sprintf("Error searching local recommendations: %v", err)
				}
				sendSSE(w, "tool_result", map[string]string{"name": "search_local_recommendations"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, summary, err != nil))

			case "get_weather":
				result, isErr := runGetWeatherTool(ctx, variant.Input)
				sendSSE(w, "tool_result", map[string]string{"name": "get_weather"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, result, isErr))

			case "get_trip":
				result, isErr := runGetTripTool(ctx, authed, uid, variant.Input)
				sendSSE(w, "tool_result", map[string]string{"name": "get_trip"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, result, isErr))

			case "add_booking_todo":
				result, isErr := runAddBookingTodoTool(ctx, authed, uid, variant.Input)
				sendSSE(w, "tool_result", map[string]string{"name": "add_booking_todo"})
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, result, isErr))
			}
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
