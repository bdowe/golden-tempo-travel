package main

import (
	"net/http"
	"testing"

	"github.com/google/uuid"
)

func addStay(t *testing.T, token, tripID, name string) string {
	t.Helper()
	rec := doJSON(t, "POST", "/api/v1/trips/"+tripID+"/accommodations", token, map[string]any{
		"name": name,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add stay %q = %d: %s", name, rec.Code, rec.Body.String())
	}
	return decode(t, rec)["id"].(string)
}

func addSegment(t *testing.T, token, tripID, origin, destination string) string {
	t.Helper()
	rec := doJSON(t, "POST", "/api/v1/trips/"+tripID+"/segments", token, map[string]any{
		"mode": "flight", "origin": origin, "destination": destination,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add segment %s->%s = %d: %s", origin, destination, rec.Code, rec.Body.String())
	}
	return decode(t, rec)["id"].(string)
}

func idsOf(rows []map[string]any) []string {
	out := make([]string, 0, len(rows))
	for _, r := range rows {
		out = append(out, r["id"].(string))
	}
	return out
}

func assertIDOrder(t *testing.T, rows []map[string]any, want []string, label string) {
	t.Helper()
	got := idsOf(rows)
	if len(got) != len(want) {
		t.Fatalf("%s: %d rows, want %d", label, len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("%s[%d] = %s, want %s (full: %v)", label, i, got[i], want[i], got)
		}
	}
}

// Reordering one bookings-hub group persists and leaves the other alone; the
// public share view reflects the editor's manual order.
func TestReorderBookings(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	s1 := addStay(t, token, tripID, "Hotel Alpha")
	s2 := addStay(t, token, tripID, "Hotel Beta")
	s3 := addStay(t, token, tripID, "Hotel Gamma")
	g1 := addSegment(t, token, tripID, "JFK", "LIS")
	g2 := addSegment(t, token, tripID, "LIS", "JFK")

	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/bookings/order", token, map[string]any{
		"stay_ids": []string{s3, s1, s2},
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("reorder stays = %d: %s", rec.Code, rec.Body.String())
	}

	body := decode(t, doJSON(t, "GET", "/api/v1/trips/"+tripID, token, nil))
	assertIDOrder(t, listOf(t, body, "accommodations"), []string{s3, s1, s2}, "stays")
	assertIDOrder(t, listOf(t, body, "segments"), []string{g1, g2}, "segments untouched")

	rec = doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/bookings/order", token, map[string]any{
		"segment_ids": []string{g2, g1},
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("reorder segments = %d: %s", rec.Code, rec.Body.String())
	}
	body = decode(t, doJSON(t, "GET", "/api/v1/trips/"+tripID, token, nil))
	assertIDOrder(t, listOf(t, body, "accommodations"), []string{s3, s1, s2}, "stays kept")
	assertIDOrder(t, listOf(t, body, "segments"), []string{g2, g1}, "segments")

	// The read-only share surface renders the same manual order.
	shareToken := createShare(t, token, tripID, "viewer")
	shared := decode(t, doJSON(t, "GET", "/api/v1/shared/"+shareToken, "", nil))
	sharedTrip, ok := shared["trip"].(map[string]any)
	if !ok {
		t.Fatalf("shared response missing trip: %v", shared)
	}
	assertIDOrder(t, listOf(t, sharedTrip, "accommodations"), []string{s3, s1, s2}, "shared stays")
	assertIDOrder(t, listOf(t, sharedTrip, "segments"), []string{g2, g1}, "shared segments")
}

// Draft (auto) rows are orderable and their user-assigned order survives the
// per-load drafts sync; newly seeded drafts take the 9999 default and land
// last; confirming a draft keeps the order.
func TestReorderBookingsDraftsKeepOrder(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	confirmed := addStay(t, token, tripID, "Hotel Confirmed")
	body := syncDrafts(t, token, tripID, []map[string]any{lisbonStay()}, nil)
	draft := findByKey(listOf(t, body, "accommodations"), "stay:lisbon")
	if draft == nil {
		t.Fatalf("draft not seeded: %v", body)
	}
	draftID := draft["id"].(string)

	// Put the draft ahead of the confirmed stay.
	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/bookings/order", token, map[string]any{
		"stay_ids": []string{draftID, confirmed},
	})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("reorder = %d: %s", rec.Code, rec.Body.String())
	}

	// The same sync that seeded the draft re-upserts it — order must hold.
	body = syncDrafts(t, token, tripID, []map[string]any{lisbonStay()}, nil)
	assertIDOrder(t, listOf(t, body, "accommodations"), []string{draftID, confirmed}, "after re-sync")

	// A newly seeded draft (9999 default) sinks below the ordered rows.
	porto := map[string]any{"auto_key": "stay:porto", "name": "Stay in Porto"}
	body = syncDrafts(t, token, tripID, []map[string]any{lisbonStay(), porto}, nil)
	stays := listOf(t, body, "accommodations")
	newDraft := findByKey(stays, "stay:porto")
	if newDraft == nil {
		t.Fatalf("new draft not seeded: %v", stays)
	}
	assertIDOrder(t, stays, []string{draftID, confirmed, newDraft["id"].(string)}, "new draft last")

	// Confirming the reordered draft (empty PATCH) keeps its position.
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/accommodations/"+draftID, token, map[string]any{}); rec.Code != http.StatusOK {
		t.Fatalf("confirm draft = %d: %s", rec.Code, rec.Body.String())
	}
	body = decode(t, doJSON(t, "GET", "/api/v1/trips/"+tripID, token, nil))
	assertIDOrder(t, listOf(t, body, "accommodations"),
		[]string{draftID, confirmed, newDraft["id"].(string)}, "after confirm")
}

func TestReorderBookingsValidation(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()
	s1 := addStay(t, token, tripID, "Hotel Alpha")
	addStay(t, token, tripID, "Hotel Beta")
	g1 := addSegment(t, token, tripID, "JFK", "LIS")

	cases := []struct {
		name string
		body map[string]any
		want int
	}{
		{"both empty", map[string]any{}, http.StatusBadRequest},
		{"unknown id", map[string]any{"stay_ids": []string{uuid.NewString()}}, http.StatusConflict},
		{"malformed id", map[string]any{"stay_ids": []string{"not-a-uuid"}}, http.StatusConflict},
		{"duplicate id", map[string]any{"stay_ids": []string{s1, s1}}, http.StatusConflict},
		{"segment id in stay_ids", map[string]any{"stay_ids": []string{g1}}, http.StatusConflict},
		{"stay id in segment_ids", map[string]any{"segment_ids": []string{s1}}, http.StatusConflict},
		{"subset ok", map[string]any{"stay_ids": []string{s1}}, http.StatusNoContent},
	}
	for _, tc := range cases {
		rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/bookings/order", token, tc.body)
		if rec.Code != tc.want {
			t.Fatalf("%s = %d, want %d: %s", tc.name, rec.Code, tc.want, rec.Body.String())
		}
	}

	_, strangerToken := createTestUser(t, "stranger@example.com")
	if rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/bookings/order", strangerToken, map[string]any{
		"stay_ids": []string{s1},
	}); rec.Code != http.StatusNotFound {
		t.Fatalf("stranger reorder = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/bookings/order", "", map[string]any{
		"stay_ids": []string{s1},
	}); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous reorder = %d, want 401", rec.Code)
	}
}
