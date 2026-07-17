package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

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

var updateBookingTodoTool = anthropic.ToolParam{
	Name:        "update_booking_todo",
	Description: anthropic.String("Update an item on a saved trip's booking checklist when the plan changed and the item is now wrong or stale (different destination, moved dates, another provider). Pass only the fields you're changing. Items marked 'auto' in get_trip track the itinerary and cannot be edited. Requires the trip's id and the item's todo_id — call get_trip first to see the checklist with ids."),
	InputSchema: anthropic.ToolInputSchemaParam{
		Properties: map[string]any{
			"trip_id": map[string]any{
				"type":        "string",
				"description": "The saved trip's id",
			},
			"todo_id": map[string]any{
				"type":        "string",
				"description": "The checklist item's todo_id from get_trip",
			},
			"title": map[string]any{
				"type":        "string",
				"description": "New short imperative label",
			},
			"subtitle": map[string]any{
				"type":        "string",
				"description": "New detail line",
			},
			"kind": map[string]any{
				"type":        "string",
				"description": "'stay', 'transport', or 'other'",
			},
			"depart_date": map[string]any{
				"type":        "string",
				"description": "New YYYY-MM-DD the booking is for",
			},
			"booked": map[string]any{
				"type":        "boolean",
				"description": "Mark the item booked (true) or not booked (false)",
			},
		},
		Required: []string{"trip_id", "todo_id"},
	},
}

var removeBookingTodoTool = anthropic.ToolParam{
	Name:        "remove_booking_todo",
	Description: anthropic.String("Remove an item from a saved trip's booking checklist when it no longer applies (e.g. the destination or plan changed and the booking is moot). Items marked 'auto' in get_trip cannot be removed — they track the itinerary automatically. Call get_trip first to get the item's todo_id."),
	InputSchema: anthropic.ToolInputSchemaParam{
		Properties: map[string]any{
			"trip_id": map[string]any{
				"type":        "string",
				"description": "The saved trip's id",
			},
			"todo_id": map[string]any{
				"type":        "string",
				"description": "The checklist item's todo_id from get_trip",
			},
		},
		Required: []string{"trip_id", "todo_id"},
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

func runGetTripTool(ctx context.Context, authed bool, uid uuid.UUID, boundTripID *uuid.UUID, input json.RawMessage) (string, bool) {
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
	// The bound trip of a refine session may be one the caller co-plans rather
	// than owns; everything else stays strictly caller-owned (a collaborator
	// must never browse the owner's other trips).
	var trip store.Trip
	if boundTripID != nil && tid == *boundTripID {
		trip, err = q.GetEditableTripByID(ctx, store.GetEditableTripByIDParams{ID: tid, UserID: uid})
	} else {
		trip, err = q.GetTripByIDAndOwner(ctx, store.GetTripByIDAndOwnerParams{ID: tid, UserID: uid})
	}
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
	// Booking checklist with ids so the agent can update/remove stale items;
	// degrade silently on error — the itinerary alone is still useful.
	if todos, err := q.ListBookingTodosByTrip(ctx, trip.ID); err == nil && len(todos) > 0 {
		fmt.Fprintf(&b, "Booking checklist (%d items):\n", len(todos))
		for _, td := range todos {
			status := "not booked"
			if td.Booked {
				status = "booked"
			}
			origin := "added by traveler"
			switch {
			case td.Auto:
				origin = "auto — tracks the itinerary; not editable"
			case strings.HasPrefix(td.TodoKey, "agent:"):
				origin = "agent-added"
			}
			fmt.Fprintf(&b, "- %q [todo_id: %s] (%s, %s, %s)\n", td.Title, td.ID, td.Kind, status, origin)
		}
	}
	return b.String(), false
}

// checkBookingTodoSession is the shared guard ladder for the booking-todo
// tools: signed-in, persistence up, valid trip_id owned by the caller.
func checkBookingTodoSession(s *planSession, tripID string) (uuid.UUID, string, bool) {
	if !s.authed {
		return uuid.Nil, "The traveler is not signed in, so nothing can be saved. Give the advice in your reply instead.", true
	}
	if dbPool == nil {
		return uuid.Nil, "Booking checklists are unavailable right now (persistence offline).", true
	}
	tid, err := uuid.Parse(strings.TrimSpace(tripID))
	if err != nil {
		return uuid.Nil, "That trip_id is not valid; call get_trip to find the right one.", true
	}
	// The agent may write to the caller's own trips, or to the bound trip of
	// a refine session the caller can edit (owner or collaborator).
	if s.boundTripID != nil && tid == *s.boundTripID {
		if _, err := store.New(dbPool).GetEditableTripByID(s.ctx, store.GetEditableTripByIDParams{ID: tid, UserID: s.uid}); err != nil {
			return uuid.Nil, "No such trip for this traveler; call get_trip to find the right one.", true
		}
	} else if _, err := store.New(dbPool).GetTripByIDAndOwner(s.ctx, store.GetTripByIDAndOwnerParams{ID: tid, UserID: s.uid}); err != nil {
		return uuid.Nil, "No such trip for this traveler; call get_trip to find the right one.", true
	}
	return tid, "", false
}

func runAddBookingTodoTool(s *planSession, input json.RawMessage) (string, bool) {
	var in struct {
		TripID     string  `json:"trip_id"`
		Kind       string  `json:"kind"`
		Title      string  `json:"title"`
		Subtitle   *string `json:"subtitle"`
		DepartDate *string `json:"depart_date"`
	}
	json.Unmarshal(input, &in)

	tid, msg, failed := checkBookingTodoSession(s, in.TripID)
	if failed {
		return msg, true
	}
	kind := strings.TrimSpace(in.Kind)
	if !allowedBookingKinds[kind] {
		return "kind must be 'stay', 'transport', or 'other'.", true
	}
	if strings.TrimSpace(in.Title) == "" {
		return "title is required.", true
	}
	depart, err := parseDateParam(in.DepartDate)
	if err != nil {
		return "depart_date must be YYYY-MM-DD.", true
	}

	todo, err := store.New(dbPool).CreateBookingTodo(s.ctx, store.CreateBookingTodoParams{
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
	touchTripAs(s.ctx, tid, s.uid)
	sendSSE(s.w, "trip_updated", map[string]string{"trip_id": tid.String()})
	go recordEvent(s.uid, "agent_booking_todo_added", &tid, map[string]any{"kind": todo.Kind})
	return fmt.Sprintf("Added %q to the trip's booking checklist. Mention it briefly; the traveler will see it on the trip page.", todo.Title), false
}

// touchTripAs stamps a content edit made through an agent tool (best-effort;
// the write itself already committed). Same invariant as TouchTrip: real
// edits only, never passive loads.
func touchTripAs(ctx context.Context, tripID, actor uuid.UUID) {
	_ = store.New(dbPool).TouchTrip(ctx, store.TouchTripParams{
		ID: tripID, UpdatedBy: pgtype.UUID{Bytes: actor, Valid: true},
	})
}

// bookingTodoMissingMsg covers both "wrong id" and "auto row" — the queries
// exclude auto=true rows, so the two cases are indistinguishable here.
const bookingTodoMissingMsg = "No such checklist item on that trip, or it's an auto item managed from the itinerary — those can't be changed. Call get_trip to see the current checklist."

func runUpdateBookingTodoTool(s *planSession, input json.RawMessage) (string, bool) {
	var in struct {
		TripID     string  `json:"trip_id"`
		TodoID     string  `json:"todo_id"`
		Title      *string `json:"title"`
		Subtitle   *string `json:"subtitle"`
		Kind       *string `json:"kind"`
		DepartDate *string `json:"depart_date"`
		Booked     *bool   `json:"booked"`
	}
	json.Unmarshal(input, &in)

	tid, msg, failed := checkBookingTodoSession(s, in.TripID)
	if failed {
		return msg, true
	}
	todoID, err := uuid.Parse(strings.TrimSpace(in.TodoID))
	if err != nil {
		return "That todo_id is not valid; call get_trip to see the checklist with ids.", true
	}
	if in.Kind != nil && !allowedBookingKinds[strings.TrimSpace(*in.Kind)] {
		return "kind must be 'stay', 'transport', or 'other'.", true
	}
	if in.Title != nil {
		t := strings.TrimSpace(*in.Title)
		if t == "" {
			return "title cannot be empty.", true
		}
		in.Title = &t
	}
	depart, err := parseDateParam(in.DepartDate)
	if err != nil {
		return "depart_date must be YYYY-MM-DD.", true
	}
	if in.Title == nil && in.Subtitle == nil && in.Kind == nil && in.DepartDate == nil && in.Booked == nil {
		return "Pass at least one field to change (title, subtitle, kind, depart_date, or booked).", true
	}

	todo, err := store.New(dbPool).UpdateBookingTodo(s.ctx, store.UpdateBookingTodoParams{
		ID:         todoID,
		TripID:     tid,
		Kind:       in.Kind,
		Title:      in.Title,
		Subtitle:   in.Subtitle,
		DepartDate: depart,
		Booked:     in.Booked,
	})
	if err != nil {
		return bookingTodoMissingMsg, true
	}
	touchTripAs(s.ctx, tid, s.uid)
	sendSSE(s.w, "trip_updated", map[string]string{"trip_id": tid.String()})
	go recordEvent(s.uid, "agent_booking_todo_updated", &tid, map[string]any{"kind": todo.Kind})
	return fmt.Sprintf("Updated %q on the trip's booking checklist — the traveler's trip page has refreshed.", todo.Title), false
}

func runRemoveBookingTodoTool(s *planSession, input json.RawMessage) (string, bool) {
	var in struct {
		TripID string `json:"trip_id"`
		TodoID string `json:"todo_id"`
	}
	json.Unmarshal(input, &in)

	tid, msg, failed := checkBookingTodoSession(s, in.TripID)
	if failed {
		return msg, true
	}
	todoID, err := uuid.Parse(strings.TrimSpace(in.TodoID))
	if err != nil {
		return "That todo_id is not valid; call get_trip to see the checklist with ids.", true
	}

	rows, err := store.New(dbPool).DeleteBookingTodoNonAuto(s.ctx, store.DeleteBookingTodoNonAutoParams{ID: todoID, TripID: tid})
	if err != nil || rows == 0 {
		return bookingTodoMissingMsg, true
	}
	touchTripAs(s.ctx, tid, s.uid)
	sendSSE(s.w, "trip_updated", map[string]string{"trip_id": tid.String()})
	go recordEvent(s.uid, "agent_booking_todo_removed", &tid, nil)
	return "Removed the item from the trip's booking checklist — the traveler's trip page has refreshed.", false
}
