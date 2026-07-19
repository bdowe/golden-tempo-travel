package main

import (
	"net/http"
	"testing"
)

// Negative-input QA sweep (Hardening PR3). Proves the shared validators and the
// per-trip data-volume caps reject bad input across the CRUD write handlers.
// Uses the requireDB/resetDB/doJSON harness in integration_test.go.

func TestValidationRejectsBadCoords(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	base := "/api/v1/trips/" + trip.ID.String()

	// Itinerary item with an out-of-range latitude → 400.
	if rec := doJSON(t, "POST", base+"/items", token, map[string]any{
		"name": "Bad Coords", "latitude": 9999.0, "longitude": 12.0,
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("item lat=9999 = %d, want 400: %s", rec.Code, rec.Body.String())
	}

	// Accommodation with an out-of-range longitude → 400.
	if rec := doJSON(t, "POST", base+"/accommodations", token, map[string]any{
		"name": "Bad Hotel", "latitude": 12.0, "longitude": 9999.0,
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("accommodation lng=9999 = %d, want 400: %s", rec.Code, rec.Body.String())
	}
}

func TestValidationRejectsEmptyTripTitle(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)

	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+trip.ID.String(), token, map[string]any{
		"title": "   ",
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("empty trip title = %d, want 400: %s", rec.Code, rec.Body.String())
	}

	// Over-length title → 400.
	long := make([]byte, maxNameLen+1)
	for i := range long {
		long[i] = 'a'
	}
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+trip.ID.String(), token, map[string]any{
		"title": string(long),
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("over-length trip title = %d, want 400", rec.Code)
	}
}

func TestValidationRejectsHugeDay(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	base := "/api/v1/trips/" + trip.ID.String()

	if rec := doJSON(t, "POST", base+"/items", token, map[string]any{
		"name": "Far Future", "latitude": 1.0, "longitude": 2.0, "day": 1000000000,
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("day=1e9 = %d, want 400: %s", rec.Code, rec.Body.String())
	}
}

func TestValidationRejectsOversizedLabel(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	base := "/api/v1/trips/" + trip.ID.String()

	long := make([]byte, maxNameLen+1)
	for i := range long {
		long[i] = 'x'
	}
	if rec := doJSON(t, "POST", base+"/budget/expenses", token, map[string]any{
		"category": "food", "label": string(long), "amount": 10.0,
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("over-length expense label = %d, want 400: %s", rec.Code, rec.Body.String())
	}
}

func TestItemVolumeCap(t *testing.T) {
	resetDB(t)
	t.Setenv("MAX_ITEMS_PER_TRIP", "2")
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 2) // already at the cap
	base := "/api/v1/trips/" + trip.ID.String()

	if rec := doJSON(t, "POST", base+"/items", token, map[string]any{
		"name": "One Too Many", "latitude": 1.0, "longitude": 2.0,
	}); rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("item over cap = %d, want 422: %s", rec.Code, rec.Body.String())
	}
}

func TestExpenseVolumeCap(t *testing.T) {
	resetDB(t)
	t.Setenv("MAX_EXPENSES_PER_TRIP", "1")
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	base := "/api/v1/trips/" + trip.ID.String()

	// First expense fits.
	if rec := doJSON(t, "POST", base+"/budget/expenses", token, map[string]any{
		"category": "food", "label": "Lunch", "amount": 12.0,
	}); rec.Code != http.StatusCreated {
		t.Fatalf("first expense = %d, want 201: %s", rec.Code, rec.Body.String())
	}
	// Second is over the cap.
	if rec := doJSON(t, "POST", base+"/budget/expenses", token, map[string]any{
		"category": "food", "label": "Dinner", "amount": 30.0,
	}); rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expense over cap = %d, want 422: %s", rec.Code, rec.Body.String())
	}
}
