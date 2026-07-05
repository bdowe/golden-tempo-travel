package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/google/uuid"

	"travel-route-planner/store"
)

// The Wave-6 agent tools (weather, saved-trip context, booking write-back).
// Definitions and dispatchers live here so plan_handler.go's switch stays a
// thin router. Each dispatcher returns (resultText, isError) and never
// panics on degraded mode — the model gets a usable sentence either way.

var getWeatherTool = anthropic.ToolParam{
	Name:        "get_weather",
	Description: anthropic.String("Get the weather for a city over the trip dates: a real forecast when the dates are within ~2 weeks, otherwise last year's observed weather for the same dates as a seasonal guide. Use it when weather changes the advice — packing, beach/ski viability, outdoor days, seasonal closures."),
	InputSchema: anthropic.ToolInputSchemaParam{
		Properties: map[string]any{
			"city": map[string]any{
				"type":        "string",
				"description": "City or island name, e.g. 'Athens' or 'Naxos'",
			},
			"start_date": map[string]any{
				"type":        "string",
				"description": "First day, YYYY-MM-DD",
			},
			"end_date": map[string]any{
				"type":        "string",
				"description": "Last day, YYYY-MM-DD; omit for a single day",
			},
		},
		Required: []string{"city", "start_date"},
	},
}

var getTripTool = anthropic.ToolParam{
	Name:        "get_trip",
	Description: anthropic.String("Read the traveler's saved trips. Without trip_id: list their trips (id, title, dates, cities). With trip_id: the full itinerary of that trip. Use it when they reference an existing trip ('my Lisbon trip', 'the trip we planned last week') so you can build on what's already saved instead of asking again."),
	InputSchema: anthropic.ToolInputSchemaParam{
		Properties: map[string]any{
			"trip_id": map[string]any{
				"type":        "string",
				"description": "A trip id from a previous get_trip listing; omit to list all trips",
			},
		},
	},
}

var addBookingTodoTool = anthropic.ToolParam{
	Name:        "add_booking_todo",
	Description: anthropic.String("Add an item to a saved trip's booking checklist (e.g. 'Book the Naxos ferry', 'Reserve the tasting menu at Belcanto'). Use it when you give time-sensitive booking advice about one of the traveler's saved trips, so the advice becomes a tracked to-do instead of a chat message they'll lose. Requires the trip's id (use get_trip first if you don't have it)."),
	InputSchema: anthropic.ToolInputSchemaParam{
		Properties: map[string]any{
			"trip_id": map[string]any{
				"type":        "string",
				"description": "The saved trip's id",
			},
			"kind": map[string]any{
				"type":        "string",
				"description": "'stay', 'transport', or 'other'",
			},
			"title": map[string]any{
				"type":        "string",
				"description": "Short imperative label, e.g. 'Book Blue Star ferry Athens → Naxos'",
			},
			"subtitle": map[string]any{
				"type":        "string",
				"description": "Optional detail, e.g. 'books out ~2 weeks ahead in July'",
			},
			"depart_date": map[string]any{
				"type":        "string",
				"description": "Optional YYYY-MM-DD the booking is for",
			},
		},
		Required: []string{"trip_id", "kind", "title"},
	},
}

func runGetWeatherTool(ctx context.Context, input json.RawMessage) (string, bool) {
	var in struct {
		City      string `json:"city"`
		StartDate string `json:"start_date"`
		EndDate   string `json:"end_date"`
	}
	json.Unmarshal(input, &in)
	report, err := weatherService.GetTripWeather(ctx, in.City, in.StartDate, in.EndDate)
	if err != nil {
		return fmt.Sprintf("Could not get weather for %s: %v. Plan without it.", in.City, err), true
	}
	return summarizeWeather(report), false
}

func runGetTripTool(ctx context.Context, authed bool, uid uuid.UUID, input json.RawMessage) (string, bool) {
	if !authed {
		return "The traveler is not signed in, so there are no saved trips to read. Continue planning in this conversation.", true
	}
	if dbPool == nil {
		return "Saved trips are unavailable right now (persistence offline).", true
	}
	var in struct {
		TripID string `json:"trip_id"`
	}
	json.Unmarshal(input, &in)
	q := store.New(dbPool)

	if strings.TrimSpace(in.TripID) == "" {
		trips, err := q.ListLatestTripsByOwner(ctx, uid)
		if err != nil {
			return "Could not load the traveler's trips.", true
		}
		if len(trips) == 0 {
			return "The traveler has no saved trips yet.", false
		}
		var b strings.Builder
		fmt.Fprintf(&b, "The traveler's saved trips (%d):\n", len(trips))
		for _, t := range trips {
			line := fmt.Sprintf("- %s [id: %s] — %s", t.Title, t.ID, t.Status)
			if d := dateString(t.StartDate); d != "" {
				line += ", starts " + d
			}
			if len(t.Cities) > 0 {
				line += ", cities: " + strings.Join(t.Cities, ", ")
			}
			b.WriteString(line + "\n")
		}
		b.WriteString("Call get_trip with a trip_id for the full itinerary.")
		return b.String(), false
	}

	tid, err := uuid.Parse(in.TripID)
	if err != nil {
		return "That trip_id is not valid; call get_trip without arguments to list trips.", true
	}
	trip, err := q.GetTripByIDAndOwner(ctx, store.GetTripByIDAndOwnerParams{ID: tid, UserID: uid})
	if err != nil {
		return "No such trip for this traveler; call get_trip without arguments to list trips.", true
	}
	items, err := q.GetItineraryItemsByTrip(ctx, trip.ID)
	if err != nil {
		return "Could not load that trip's itinerary.", true
	}

	var b strings.Builder
	fmt.Fprintf(&b, "Trip %q [id: %s], status %s", trip.Title, trip.ID, trip.Status)
	if d := dateString(trip.StartDate); d != "" {
		fmt.Fprintf(&b, ", %s", d)
		if e := dateString(trip.EndDate); e != "" {
			fmt.Fprintf(&b, " to %s", e)
		}
	}
	fmt.Fprintf(&b, ". %d places:\n", len(items))
	for _, it := range items {
		line := "- " + it.Name
		var tags []string
		if it.Day != nil {
			tags = append(tags, fmt.Sprintf("day %d", *it.Day))
		}
		if it.City != nil && *it.City != "" {
			tags = append(tags, *it.City)
		}
		if it.TimeOfDay != nil && *it.TimeOfDay != "" {
			tags = append(tags, *it.TimeOfDay)
		}
		if it.Category != nil && *it.Category != "" {
			tags = append(tags, *it.Category)
		}
		if len(tags) > 0 {
			line += " (" + strings.Join(tags, ", ") + ")"
		}
		b.WriteString(line + "\n")
	}
	return b.String(), false
}

func runAddBookingTodoTool(ctx context.Context, authed bool, uid uuid.UUID, input json.RawMessage) (string, bool) {
	if !authed {
		return "The traveler is not signed in, so nothing can be saved. Give the advice in your reply instead.", true
	}
	if dbPool == nil {
		return "Booking checklists are unavailable right now (persistence offline).", true
	}
	var in struct {
		TripID     string  `json:"trip_id"`
		Kind       string  `json:"kind"`
		Title      string  `json:"title"`
		Subtitle   *string `json:"subtitle"`
		DepartDate *string `json:"depart_date"`
	}
	json.Unmarshal(input, &in)

	kind := strings.TrimSpace(in.Kind)
	if !allowedBookingKinds[kind] {
		return "kind must be 'stay', 'transport', or 'other'.", true
	}
	if strings.TrimSpace(in.Title) == "" {
		return "title is required.", true
	}
	tid, err := uuid.Parse(strings.TrimSpace(in.TripID))
	if err != nil {
		return "That trip_id is not valid; call get_trip to find the right one.", true
	}
	// Ownership: the agent may only write to the caller's own trips.
	if _, err := store.New(dbPool).GetTripByIDAndOwner(ctx, store.GetTripByIDAndOwnerParams{ID: tid, UserID: uid}); err != nil {
		return "No such trip for this traveler; call get_trip to find the right one.", true
	}
	depart, err := parseDateParam(in.DepartDate)
	if err != nil {
		return "depart_date must be YYYY-MM-DD.", true
	}

	todo, err := store.New(dbPool).CreateBookingTodo(ctx, store.CreateBookingTodoParams{
		TripID:     tid,
		Kind:       kind,
		TodoKey:    "agent:" + uuid.NewString(),
		Title:      strings.TrimSpace(in.Title),
		Subtitle:   in.Subtitle,
		DepartDate: depart,
		Position:   9999,
	})
	if err != nil {
		return "Could not save the booking to-do.", true
	}
	go recordEvent(uid, "agent_booking_todo_added", &tid, map[string]any{"kind": todo.Kind})
	return fmt.Sprintf("Added %q to the trip's booking checklist. Mention it briefly; the traveler will see it on the trip page.", todo.Title), false
}
