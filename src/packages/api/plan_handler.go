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

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"

	"travel-route-planner/store"
)

type PlanRequest struct {
	Messages []PlanChatMessage `json:"messages"`
	ChatID   string            `json:"chat_id"`
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

	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		sendSSE(w, "error", map[string]string{"message": "ANTHROPIC_API_KEY not configured"})
		return
	}

	client := anthropic.NewClient(option.WithAPIKey(apiKey))

	// Resolve the caller once: anonymous sessions get no personalization and no
	// preference-writing tool; signed-in sessions get both.
	uid, authed := userIDFromRequest(r)

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
					"items": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"name":     map[string]any{"type": "string"},
							"place_id": map[string]any{"type": "string"},
							"address":  map[string]any{"type": "string"},
							"city": map[string]any{
								"type":        "string",
								"description": "The city/town the place is physically located in — use the actual municipality, not the nearest major city (e.g. 'Versailles', not 'Paris'). Used to group the itinerary by city.",
							},
							"day_trip_from": map[string]any{
								"type":        "string",
								"description": "If this place is a day trip from the city the traveler is staying in (a nearby town visited and returned from the same day, e.g. Versailles from Paris), set this to that hub city's name. Leave unset for places in the city you're staying in.",
							},
							"latitude":  map[string]any{"type": "number"},
							"longitude": map[string]any{"type": "number"},
							"category": map[string]any{
								"type":        "string",
								"enum":        []string{"attraction", "restaurant"},
								"description": "What kind of place this is — 'attraction' for sights/activities, 'restaurant' for places to eat.",
							},
							"time_of_day": map[string]any{
								"type":        "string",
								"enum":        []string{"morning", "afternoon", "evening"},
								"description": "Which part of the day to do this — spread a day's places sensibly (sights/activities across morning–afternoon, meals at their natural times).",
							},
							"day": map[string]any{
								"type":        "integer",
								"description": "The trip day this place belongs to, starting at 1 and increasing chronologically across the whole trip; all places on the same day share the same number (e.g. days 1–3 in Paris, then day 4 onward in Rome). Combined with time_of_day this makes each day read as a sequential schedule.",
							},
						},
						"required": []string{"name", "latitude", "longitude"},
					},
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
		Description: anthropic.String("Save what you learn about the traveler's preferences so future trips are personalized. Call this when the user reveals a budget level, trip pace, interests, or which airport they fly from. Only include fields you actually learned."),
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
		Description: anthropic.String("Give the traveler links to browse transport options. Call this when they need to get to or between destinations. Mode 'flight' returns Google Flights + Kayak; mode 'ground' returns Rome2Rio (covers trains, buses, cars, ferries)."),
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
				"optimize_for": map[string]any{"type": "string", "enum": []string{"cost", "time", "balanced"}, "description": "Ranking emphasis"},
			},
			Required: []string{"origin", "destination", "depart_date"},
		},
	}

	tools := []anthropic.ToolUnionParam{
		{OfTool: &searchTool},
		{OfTool: &createTool},
		{OfTool: &suggestStaysTool},
		{OfTool: &suggestTransportTool},
		{OfTool: &searchFlightsTool},
	}
	if authed {
		tools = append(tools, anthropic.ToolUnionParam{OfTool: &savePrefsTool})
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
	basePrompt := "You are an expert travel agent. Today's date is " + today.Format("Monday, January 2, 2006") + " (" + today.Format("2006-01-02") + "). When a traveler gives a date without a year, assume the soonest upcoming occurrence on or after today — never a past year. Use dates in YYYY-MM-DD form when calling tools. Help users plan trips by searching for specific places and attractions. Use search_places to find real locations with coordinates. Search for individual places (e.g. 'Louvre Museum Paris') rather than broad queries. Include a mix of activities/attractions and dining (restaurants), guided by the traveler's interests, budget, and pace. When you call create_itinerary, tag each location with category ('attraction' or 'restaurant'), a time_of_day ('morning', 'afternoon', or 'evening'), and a day (the 1-based trip day it falls on, increasing chronologically across the whole trip) so each day reads as a sensible schedule. When you have gathered enough places for the user's trip, call create_itinerary to finalize the plan; pass start_date (and end_date) whenever the traveler has given or agreed to travel dates, with day 1 being the start date. You can also use search_flights to find real flight options — ask for the traveler's departure city/airport and dates if you don't know them, and pick optimize_for from their budget (budget→cost, luxury→time, otherwise balanced); the ranked options are shown to the traveler as cards, so summarize and help them choose. Be conversational and helpful — ask clarifying questions if needed before searching."

	placesService := NewGooglePlacesService()
	ctx := r.Context()

	// Fold the signed-in traveler's saved preferences into the system prompt.
	systemPrompt := basePrompt
	if authed {
		if prefs, err := store.New(dbPool).GetPreferences(ctx, uid); err == nil {
			systemPrompt = personalizedSystemPrompt(basePrompt, &prefs)
		}
	}

	for {
		params := anthropic.MessageNewParams{
			Model:     anthropic.ModelClaudeSonnet4_6,
			MaxTokens: 4096,
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

				donePayload := map[string]any{"locations": in.Locations, "summary": in.Summary}
				// Persist the trip only for signed-in callers; anonymous sessions
				// stay ephemeral (no trip_id in the done event).
				if authed {
					if tripID, err := persistTrip(ctx, uid, req.ChatID, in.Title, in.Summary, in.StartDate, in.EndDate, in.Locations); err != nil {
						log.Printf("failed to persist trip: %v", err)
					} else {
						donePayload["trip_id"] = tripID
					}
				}
				sendSSE(w, "done", donePayload)
				toolResults = append(toolResults, anthropic.NewToolResultBlock(variant.ID, "Itinerary created successfully.", false))

			case "save_preferences":
				var in struct {
					Budget      *string  `json:"budget"`
					Pace        *string  `json:"pace"`
					Interests   []string `json:"interests"`
					HomeAirport *string  `json:"home_airport"`
				}
				json.Unmarshal(variant.Input, &in)

				budget, _ := normalizeChoice(in.Budget, allowedBudgets, "budget")
				pace, _ := normalizeChoice(in.Pace, allowedPaces, "pace")
				homeAirport, _ := normalizeAirportCode(in.HomeAirport)
				var interestsArg interface{}
				if in.Interests != nil {
					interestsArg = normalizeInterests(in.Interests)
				}
				_, err := store.New(dbPool).UpsertPreferences(ctx, store.UpsertPreferencesParams{
					UserID: uid, Budget: budget, Pace: pace, Interests: interestsArg, HomeAirport: homeAirport,
				})
				msg := "Preferences saved."
				if err != nil {
					msg = fmt.Sprintf("Could not save preferences: %v", err)
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

			case "search_flights":
				var in struct {
					Origin      string `json:"origin"`
					Destination string `json:"destination"`
					DepartDate  string `json:"depart_date"`
					ReturnDate  string `json:"return_date"`
					Adults      int    `json:"adults"`
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
					ReturnDate: in.ReturnDate, Adults: adults, OptimizeFor: in.OptimizeFor,
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
			}
		}

		messages = append(messages, anthropic.NewUserMessage(toolResults...))

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
// so it can describe and compare them without re-sending the full payload (which
// already reached the UI via the "flights" event).
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
	b.WriteString("These option cards are already shown to the traveler; summarize and help them choose.")
	return b.String()
}

// personalizedSystemPrompt appends the traveler's saved preferences to the base
// prompt, omitting any fields that are unset. Returns base unchanged when there
// are no preferences to add.
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
	if len(parts) == 0 {
		return base
	}
	return base + "\n\nTraveler preferences — " + strings.Join(parts, "; ") +
		". Tailor your suggestions accordingly." + homeNote
}
