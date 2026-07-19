package main

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// Pure unit tests for the individual review checks — hand-built exportData, no
// DB. These exercise the deterministic rules in isolation.

func dateVal(t *testing.T, s string) pgtype.Date {
	t.Helper()
	tm, err := time.Parse("2006-01-02", s)
	if err != nil {
		t.Fatalf("parse date %q: %v", s, err)
	}
	return pgtype.Date{Time: tm, Valid: true}
}

func i32p(v int32) *int32 { return &v }

func TestCheckDates_Undated(t *testing.T) {
	d := exportData{Trip: store.Trip{ID: uuid.New(), Status: "draft"}}
	fs := checkDates(d)
	if len(fs) != 1 || fs[0].Category != "dates" || fs[0].Severity != "info" {
		t.Fatalf("undated trip = %+v", fs)
	}
}

func TestCheckDates_ItemPastSpan(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03")} // 3-day span
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Louvre", Day: i32p(2)},
		{ID: uuid.New(), Name: "Way Out", Day: i32p(9)},
	}
	fs := checkDates(exportData{Trip: trip, Items: items})
	if len(fs) != 1 || fs[0].Severity != "warn" || fs[0].Day == nil || *fs[0].Day != 9 {
		t.Fatalf("past-span = %+v", fs)
	}
}

func TestCheckUnscheduled_Grouped(t *testing.T) {
	d := exportData{Trip: store.Trip{ID: uuid.New()}, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "A"}, // day nil
		{ID: uuid.New(), Name: "B"}, // day nil
		{ID: uuid.New(), Name: "C", Day: i32p(1)},
	}}
	fs := checkUnscheduled(d)
	if len(fs) != 1 || fs[0].Category != "unscheduled" {
		t.Fatalf("unscheduled = %+v", fs)
	}
}

func TestCheckDensity_EmptyAndPacked(t *testing.T) {
	morning := strp("morning")
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "A", Day: i32p(1), TimeOfDay: morning},
		{ID: uuid.New(), Name: "B", Day: i32p(1), TimeOfDay: morning}, // two mornings on day 1
		// day 2 empty
		{ID: uuid.New(), Name: "C", Day: i32p(3)},
	}
	fs := checkDensity(exportData{Trip: store.Trip{ID: uuid.New()}, Items: items})
	cats := map[string][]Finding{}
	for _, f := range fs {
		cats[f.Severity] = append(cats[f.Severity], f)
	}
	if len(cats["info"]) != 1 { // day 2 empty
		t.Fatalf("expected one empty-day info, got %+v", fs)
	}
	if len(cats["warn"]) != 1 { // two mornings day 1
		t.Fatalf("expected one over-packed warn, got %+v", fs)
	}
}

func TestCheckLodging_GateAndCoverage(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-04")} // 3 nights: 1,2,3

	// No accommodations, planned → all 3 nights flagged.
	fs := checkLodging(exportData{Trip: trip})
	if len(fs) != 3 {
		t.Fatalf("planned no-lodging = %d findings, want 3: %+v", len(fs), fs)
	}

	// One stay covering nights 1-2 (checkout 08-03, exclusive) → only night 3 flagged.
	acc := []store.Accommodation{{ID: uuid.New(), Name: "Hotel",
		CheckIn: dateVal(t, "2026-08-01"), CheckOut: dateVal(t, "2026-08-03")}}
	fs = checkLodging(exportData{Trip: trip, Accommodations: acc})
	if len(fs) != 1 || fs[0].Day == nil || *fs[0].Day != 3 {
		t.Fatalf("partial lodging = %+v", fs)
	}

	// Empty draft (draft status, no accommodations) is not nagged.
	draft := trip
	draft.Status = "draft"
	if fs := checkLodging(exportData{Trip: draft}); len(fs) != 0 {
		t.Fatalf("empty draft should be silent, got %+v", fs)
	}
}

func TestCheckTransit_MissingLeg(t *testing.T) {
	trip := store.Trip{ID: uuid.New()}
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Colosseum", City: strp("Rome"), Day: i32p(1)},
		{ID: uuid.New(), Name: "Duomo", City: strp("Florence"), Day: i32p(2)},
	}
	// No segments → missing Rome→Florence leg.
	fs := checkTransit(exportData{Trip: trip, Items: items})
	if len(fs) != 1 || fs[0].Category != "transit" {
		t.Fatalf("missing leg = %+v", fs)
	}
	// A connecting segment suppresses it.
	segs := []store.TripSegment{{ID: uuid.New(), Mode: "train",
		Origin: strp("Rome"), Destination: strp("Florence")}}
	if fs := checkTransit(exportData{Trip: trip, Items: items, Segments: segs}); len(fs) != 0 {
		t.Fatalf("connected legs should be silent, got %+v", fs)
	}
}

func TestCheckBudget_OverBudget(t *testing.T) {
	over := -50.0
	br := &BudgetResponse{Currency: "USD", Spent: 150, Remaining: &over}
	fs := checkBudget(exportData{Trip: store.Trip{ID: uuid.New()}}, br)
	if len(fs) != 1 || fs[0].Category != "budget" || fs[0].Severity != "warn" {
		t.Fatalf("over budget = %+v", fs)
	}
	within := 10.0
	if fs := checkBudget(exportData{Trip: store.Trip{ID: uuid.New()}}, &BudgetResponse{Remaining: &within}); len(fs) != 0 {
		t.Fatalf("within budget should be silent, got %+v", fs)
	}
	if fs := checkBudget(exportData{Trip: store.Trip{ID: uuid.New()}}, nil); len(fs) != 0 {
		t.Fatalf("no budget should be silent, got %+v", fs)
	}
}

func TestCheckBookings_Unbooked(t *testing.T) {
	d := exportData{
		Trip: store.Trip{ID: uuid.New()},
		Accommodations: []store.Accommodation{
			{ID: uuid.New(), Name: "Hotel", Booked: false},
			{ID: uuid.New(), Name: "Booked Inn", Booked: true},
		},
		Segments: []store.TripSegment{
			{ID: uuid.New(), Mode: "flight", Origin: strp("JFK"), Destination: strp("CDG"), Booked: false},
		},
	}
	fs := checkBookings(d)
	if len(fs) != 2 {
		t.Fatalf("expected 2 unbooked findings, got %+v", fs)
	}
	for _, f := range fs {
		if f.Severity != "info" || f.Category != "bookings" || f.ItemID == nil {
			t.Fatalf("booking finding shape = %+v", f)
		}
	}
}

func TestReviewTrip_DeterministicOrder(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03")}
	d := exportData{Trip: trip, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "A"}, // unscheduled
	}}
	ja, _ := json.Marshal(reviewTrip(d, reviewOptions{}))
	jb, _ := json.Marshal(reviewTrip(d, reviewOptions{}))
	if string(ja) != string(jb) {
		t.Fatalf("nondeterministic order:\n%s\n%s", ja, jb)
	}
}
