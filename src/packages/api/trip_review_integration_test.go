package main

import (
	"net/http"
	"testing"
)

// Postgres-backed tests for GET /trips/{id}/review. A deliberately-broken trip
// must surface the expected finding categories; a clean trip returns none; and
// a non-owner is 404'd (owner-or-editor scoping via editableTrip).

// reviewCategories drives the review endpoint and returns the set of categories
// present in the findings.
func reviewCategories(t *testing.T, id, token string) map[string]bool {
	t.Helper()
	rec := doJSON(t, "GET", "/api/v1/trips/"+id+"/review", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET review = %d: %s", rec.Code, rec.Body.String())
	}
	body := decode(t, rec)
	found := map[string]bool{}
	for _, f := range listOf(t, body, "findings") {
		if c, ok := f["category"].(string); ok {
			found[c] = true
		}
	}
	return found
}

func TestTripReview_BrokenTrip(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	// Two items, both day=nil (unscheduled), draft status.
	trip := createTestTrip(t, owner.ID, 2)
	id := trip.ID.String()

	// Make it a planned, dated trip (unlocks lodging night-walk).
	rec := doJSON(t, "PATCH", "/api/v1/trips/"+id, ownerToken, map[string]any{
		"start_date": "2026-08-01", "end_date": "2026-08-04", "status": "planned",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("patch trip = %d: %s", rec.Code, rec.Body.String())
	}

	// An unbooked flight segment.
	rec = doJSON(t, "POST", "/api/v1/trips/"+id+"/segments", ownerToken, map[string]any{
		"mode": "flight", "origin": "JFK", "destination": "CDG",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add segment = %d: %s", rec.Code, rec.Body.String())
	}

	// Budget target 100 with a single 150 expense → over budget.
	rec = doJSON(t, "PUT", "/api/v1/trips/"+id+"/budget", ownerToken, map[string]any{"target_amount": 100})
	if rec.Code != http.StatusOK {
		t.Fatalf("put budget = %d: %s", rec.Code, rec.Body.String())
	}
	rec = doJSON(t, "POST", "/api/v1/trips/"+id+"/budget/expenses", ownerToken, map[string]any{
		"label": "Hotel", "amount": 150, "category": "lodging",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add expense = %d: %s", rec.Code, rec.Body.String())
	}

	got := reviewCategories(t, id, ownerToken)
	for _, want := range []string{"unscheduled", "lodging", "bookings", "budget"} {
		if !got[want] {
			t.Errorf("expected a %q finding, got categories %v", want, got)
		}
	}
}

func TestTripReview_CleanTrip(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	// No itinerary items → nothing unscheduled, no density/transit gaps.
	trip := createTestTrip(t, owner.ID, 0)
	id := trip.ID.String()

	rec := doJSON(t, "PATCH", "/api/v1/trips/"+id, ownerToken, map[string]any{
		"start_date": "2026-08-01", "end_date": "2026-08-04", "status": "planned",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("patch trip = %d: %s", rec.Code, rec.Body.String())
	}

	// A stay covering every night (08-01..08-03, checkout 08-04 exclusive).
	rec = doJSON(t, "POST", "/api/v1/trips/"+id+"/accommodations", ownerToken, map[string]any{
		"name": "Grand Hotel", "check_in": "2026-08-01", "check_out": "2026-08-04",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add stay = %d: %s", rec.Code, rec.Body.String())
	}
	stayID := decode(t, rec)["id"].(string)
	// Mark it booked so no bookings finding.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+id+"/accommodations/"+stayID, ownerToken, map[string]any{"booked": true})
	if rec.Code != http.StatusOK {
		t.Fatalf("book stay = %d: %s", rec.Code, rec.Body.String())
	}

	// A comfortable budget (no expenses) → within budget.
	rec = doJSON(t, "PUT", "/api/v1/trips/"+id+"/budget", ownerToken, map[string]any{"target_amount": 1000})
	if rec.Code != http.StatusOK {
		t.Fatalf("put budget = %d: %s", rec.Code, rec.Body.String())
	}

	rec = doJSON(t, "GET", "/api/v1/trips/"+id+"/review", ownerToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET review = %d: %s", rec.Code, rec.Body.String())
	}
	if fs := listOf(t, decode(t, rec), "findings"); len(fs) != 0 {
		t.Fatalf("clean trip should have no findings, got %v", fs)
	}
}

func TestTripReview_NonOwner404(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "owner@example.com")
	_, strangerToken := createTestUser(t, "stranger@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	id := trip.ID.String()

	rec := doJSON(t, "GET", "/api/v1/trips/"+id+"/review", strangerToken, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("non-owner review = %d, want 404: %s", rec.Code, rec.Body.String())
	}
}
