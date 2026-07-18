package main

import (
	"net/http"
	"strings"
	"testing"
)

// syncAutoTodo upserts one itinerary-derived (auto=true) todo and returns its id.
func syncAutoTodo(t *testing.T, token, tripID string) string {
	t.Helper()
	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-todos", token, []map[string]any{
		{"kind": "stay", "todo_key": "stay:paris", "title": "Stay in Paris", "destination": "Paris"},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("sync auto todo = %d: %s", rec.Code, rec.Body.String())
	}
	list := decodeTodoList(t, rec)
	if len(list) == 0 {
		t.Fatal("sync returned no todos")
	}
	return list[0]["id"].(string)
}

func TestPatchBookingTodoContentEdit(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	rec := doJSON(t, "POST", "/api/v1/trips/"+tripID+"/booking-todos", token, map[string]any{
		"kind": "stay", "title": "Hotel in Athens", "destination": "Athens",
		"depart_date": "2026-08-01", "return_date": "2026-08-05",
		"provider": "airbnb", "guests": 1,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add = %d: %s", rec.Code, rec.Body.String())
	}
	created := decode(t, rec)
	todoID := created["id"].(string)
	origURL, _ := created["search_url"].(string)
	if origURL == "" {
		t.Fatal("expected a built search_url on create")
	}

	// A plain content edit updates fields and leaves the link/provider alone.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+todoID, token, map[string]any{
		"kind": "stay", "title": "Aparthotel in Athens",
		"depart_date": "2026-08-02", "return_date": "2026-08-06",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("patch = %d: %s", rec.Code, rec.Body.String())
	}
	got := decode(t, rec)
	if got["title"] != "Aparthotel in Athens" || got["depart_date"] != "2026-08-02" || got["return_date"] != "2026-08-06" {
		t.Fatalf("patched fields = %v", got)
	}
	if got["search_url"] != origURL || got["provider"] != "airbnb" {
		t.Fatalf("link/provider changed without a destination: %v / %v", got["search_url"], got["provider"])
	}
	if got["booked"] != false {
		t.Fatalf("booked flipped by content edit: %v", got["booked"])
	}

	// Re-entering a destination rebuilds the search link with the new dates.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+todoID, token, map[string]any{
		"kind": "stay", "destination": "Thessaloniki", "depart_date": "2026-09-01",
		"provider": "airbnb", "guests": 2,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("rebuild patch = %d: %s", rec.Code, rec.Body.String())
	}
	got = decode(t, rec)
	newURL, _ := got["search_url"].(string)
	if newURL == "" || newURL == origURL || !strings.Contains(newURL, "Thessaloniki") {
		t.Fatalf("search_url not rebuilt: %q", newURL)
	}

	// An explicit link wins over the destination-built one.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+todoID, token, map[string]any{
		"search_url": "https://example.com/booked",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("url patch = %d: %s", rec.Code, rec.Body.String())
	}
	if got = decode(t, rec); got["search_url"] != "https://example.com/booked" {
		t.Fatalf("explicit search_url not stored: %v", got["search_url"])
	}
}

func TestPatchBookingTodoBookedPathsAndAutoRows(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	autoID := syncAutoTodo(t, token, tripID)
	customID := addCustomTodo(t, token, tripID, "Museum tickets")

	// The original booked-only contract must keep working on auto rows — that
	// path stays on SetBookingTodoBooked, which has no auto=false guard.
	rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+autoID, token, map[string]any{
		"booked": true,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("booked-only on auto row = %d: %s", rec.Code, rec.Body.String())
	}
	if got := decode(t, rec); got["booked"] != true {
		t.Fatalf("auto row booked = %v, want true", got["booked"])
	}

	// Booked-only on a custom row: unchanged behavior.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+customID, token, map[string]any{
		"booked": true,
	})
	if rec.Code != http.StatusOK || decode(t, rec)["booked"] != true {
		t.Fatalf("booked-only on custom row = %d: %s", rec.Code, rec.Body.String())
	}

	// Content edits are custom-only: an auto row answers 404.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+autoID, token, map[string]any{
		"title": "Renamed",
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("content edit on auto row = %d, want 404", rec.Code)
	}

	// A combined edit+booked on a custom row applies both.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+customID, token, map[string]any{
		"title": "Museum + audio guide", "booked": false,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("combined patch = %d: %s", rec.Code, rec.Body.String())
	}
	if got := decode(t, rec); got["title"] != "Museum + audio guide" || got["booked"] != false {
		t.Fatalf("combined patch result = %v", got)
	}
}

func TestPatchBookingTodoValidationAndAccess(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()
	todoID := addCustomTodo(t, token, tripID, "Ferry tickets")

	cases := []struct {
		name string
		body map[string]any
		want int
	}{
		{"empty body still needs booked", map[string]any{}, http.StatusBadRequest},
		{"bad kind", map[string]any{"kind": "cruise"}, http.StatusBadRequest},
		{"blank title", map[string]any{"title": "  "}, http.StatusBadRequest},
		{"bad depart date", map[string]any{"depart_date": "next tuesday"}, http.StatusBadRequest},
		{"bad return date", map[string]any{"return_date": "2026/09/01"}, http.StatusBadRequest},
		{"destination without kind", map[string]any{"destination": "Athens"}, http.StatusBadRequest},
	}
	for _, tc := range cases {
		rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+todoID, token, tc.body)
		if rec.Code != tc.want {
			t.Fatalf("%s = %d, want %d: %s", tc.name, rec.Code, tc.want, rec.Body.String())
		}
	}

	// Viewers keep the mutation 404 posture; anonymous is 401.
	_, viewerToken := createTestUser(t, "viewer@example.com")
	shareToken := createShare(t, token, tripID, "viewer")
	if rec := joinShare(t, viewerToken, shareToken); rec.Code != http.StatusOK {
		t.Fatalf("viewer join = %d: %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+todoID, viewerToken, map[string]any{
		"title": "Hijacked",
	}); rec.Code != http.StatusNotFound {
		t.Fatalf("viewer content patch = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/booking-todos/"+todoID, "", map[string]any{
		"title": "Anon",
	}); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous patch = %d, want 401", rec.Code)
	}
}
