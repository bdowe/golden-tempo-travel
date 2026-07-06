package main

import (
	"context"
	"testing"

	"github.com/google/uuid"
)

// Integration coverage for POST /api/v1/events hardening: trip_id must be
// verified (exists + caller may access it) before it can feed the attach-rate
// numerator, and metadata is constrained to the closed key set the Flutter
// tracker sends. Everything stays best-effort — bad inputs degrade the event,
// never reject it.

// clientEventRow fetches the caller's single booking_link_clicked row.
func clientEventRow(t *testing.T, userID uuid.UUID) (tripID *string, metadata map[string]any) {
	t.Helper()
	var meta map[string]any
	err := dbPool.QueryRow(context.Background(),
		`SELECT trip_id::text, metadata FROM analytics_events
		 WHERE user_id = $1 AND event_type = 'booking_link_clicked'`,
		userID).Scan(&tripID, &meta)
	if err != nil {
		t.Fatalf("clientEventRow: %v", err)
	}
	return tripID, meta
}

func postBookingClick(t *testing.T, token string, tripID *string, metadata map[string]any) {
	t.Helper()
	body := map[string]any{"event_type": "booking_link_clicked", "metadata": metadata}
	if tripID != nil {
		body["trip_id"] = *tripID
	}
	rec := doJSON(t, "POST", "/api/v1/events", token, body)
	if rec.Code != 202 {
		t.Fatalf("POST /events = %d, want 202: %s", rec.Code, rec.Body.String())
	}
}

func TestClientEventForeignTripIDIsNulled(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "trip-owner@example.com")
	stranger, strangerToken := createTestUser(t, "stranger@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	tid := trip.ID.String()
	postBookingClick(t, strangerToken, &tid, map[string]any{"provider": "duffel"})
	waitForEventCount(t, stranger.ID, "booking_link_clicked", 1)

	gotTrip, _ := clientEventRow(t, stranger.ID)
	if gotTrip != nil {
		t.Fatalf("foreign trip_id stored as %v, want NULL", *gotTrip)
	}
}

func TestClientEventFabricatedTripIDIsNulled(t *testing.T) {
	resetDB(t)
	user, token := createTestUser(t, "fabricator@example.com")

	fake := uuid.NewString()
	postBookingClick(t, token, &fake, map[string]any{"provider": "duffel"})
	waitForEventCount(t, user.ID, "booking_link_clicked", 1)

	gotTrip, _ := clientEventRow(t, user.ID)
	if gotTrip != nil {
		t.Fatalf("fabricated trip_id stored as %v, want NULL", *gotTrip)
	}

	// The attach-rate numerator must not have moved.
	var n int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(DISTINCT trip_id) FROM analytics_events
		 WHERE event_type = 'booking_link_clicked' AND trip_id IS NOT NULL`).Scan(&n); err != nil {
		t.Fatalf("attach count: %v", err)
	}
	if n != 0 {
		t.Fatalf("trips_with_booking_click = %d, want 0", n)
	}
}

func TestClientEventOwnTripIDIsKept(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "legit-owner@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	tid := trip.ID.String()
	postBookingClick(t, token, &tid, map[string]any{"provider": "Duffel", "surface": "flight_card"})
	waitForEventCount(t, owner.ID, "booking_link_clicked", 1)

	gotTrip, meta := clientEventRow(t, owner.ID)
	if gotTrip == nil || *gotTrip != tid {
		t.Fatalf("own trip_id = %v, want %s", gotTrip, tid)
	}
	// provider is lowercased at ingest (the dashboard groups on it verbatim).
	if meta["provider"] != "duffel" {
		t.Fatalf("provider = %v, want %q", meta["provider"], "duffel")
	}
	if meta["surface"] != "flight_card" {
		t.Fatalf("surface = %v, want flight_card", meta["surface"])
	}
}

// itinerary_item_added (specs/add-to-itinerary): accepted as a client event,
// with metadata "source" constrained to the closed value set the dashboard
// groups on — anything else is dropped, never stored.
func TestClientEventItineraryItemAdded(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "adder@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	tid := trip.ID.String()

	rec := doJSON(t, "POST", "/api/v1/events", token, map[string]any{
		"event_type": "itinerary_item_added",
		"trip_id":    tid,
		"metadata":   map[string]any{"source": "local_rec"},
	})
	if rec.Code != 202 {
		t.Fatalf("POST /events = %d, want 202: %s", rec.Code, rec.Body.String())
	}
	waitForEventCount(t, owner.ID, "itinerary_item_added", 1)

	var gotTrip *string
	var meta map[string]any
	if err := dbPool.QueryRow(context.Background(),
		`SELECT trip_id::text, metadata FROM analytics_events
		 WHERE user_id = $1 AND event_type = 'itinerary_item_added'`,
		owner.ID).Scan(&gotTrip, &meta); err != nil {
		t.Fatalf("event row: %v", err)
	}
	if gotTrip == nil || *gotTrip != tid {
		t.Fatalf("trip_id = %v, want %s", gotTrip, tid)
	}
	if meta["source"] != "local_rec" {
		t.Fatalf("source = %v, want local_rec", meta["source"])
	}

	// A free-form source value is dropped (closed set: local_rec/event/guide_pin).
	rec = doJSON(t, "POST", "/api/v1/events", token, map[string]any{
		"event_type": "itinerary_item_added",
		"metadata":   map[string]any{"source": "totally_made_up", "kind": "place"},
	})
	if rec.Code != 202 {
		t.Fatalf("POST /events (bogus source) = %d, want 202", rec.Code)
	}
	waitForEventCount(t, owner.ID, "itinerary_item_added", 2)
	var meta2 map[string]any
	if err := dbPool.QueryRow(context.Background(),
		`SELECT metadata FROM analytics_events
		 WHERE user_id = $1 AND event_type = 'itinerary_item_added' AND trip_id IS NULL`,
		owner.ID).Scan(&meta2); err != nil {
		t.Fatalf("second event row: %v", err)
	}
	if _, ok := meta2["source"]; ok {
		t.Fatalf("bogus source stored: %v", meta2)
	}
	if meta2["kind"] != "place" {
		t.Fatalf("kind = %v, want place", meta2["kind"])
	}
}

func TestClientEventMetadataSanitized(t *testing.T) {
	resetDB(t)
	user, token := createTestUser(t, "meta-abuser@example.com")

	long := make([]byte, maxClientMetadataValueLen+1)
	for i := range long {
		long[i] = 'x'
	}
	postBookingClick(t, token, nil, map[string]any{
		"provider": "FerryHopper",
		"surface":  string(long),     // oversized value: dropped
		"kind":     42,               // non-string value: dropped
		"evil_key": "not-in-the-set", // unknown key: dropped
		"todo_key": "flight_JFK_CDG", // allowed, kept
		"cap_kind": "active_trips",   // unknown key (server-event field): dropped
	})
	waitForEventCount(t, user.ID, "booking_link_clicked", 1)

	_, meta := clientEventRow(t, user.ID)
	want := map[string]any{"provider": "ferryhopper", "todo_key": "flight_JFK_CDG"}
	if len(meta) != len(want) {
		t.Fatalf("metadata = %v, want exactly %v", meta, want)
	}
	for k, v := range want {
		if meta[k] != v {
			t.Fatalf("metadata[%s] = %v, want %v", k, meta[k], v)
		}
	}
}
