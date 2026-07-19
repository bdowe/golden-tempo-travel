package main

import (
	"net/http"
	"strconv"

	"travel-route-planner/store"
)

// review_handler.go — GET /api/v1/trips/{id}/review. A read-only, deterministic
// projection: no writes, no external calls. Authorized exactly like the budget
// and checklist trip-scoped routes (editableTrip: owner or active editor-
// collaborator); a missing or non-editable trip 404s.

// ReviewResponse envelopes the ordered findings so the payload can grow
// (summary counts, etc.) without breaking clients.
type ReviewResponse struct {
	Findings []Finding `json:"findings"`
}

func getTripReviewHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	data, ok := loadExportData(r.Context(), trip.ID)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}

	// Budget lives outside exportData; load it the same way getBudgetHandler
	// does and hand reviewTrip the derived response so checkBudget stays pure.
	q := store.New(dbPool)
	var budget *store.TripBudget
	if b, err := q.GetBudgetByTrip(r.Context(), trip.ID); err == nil {
		budget = &b
	}
	expenses, err := q.ListExpensesByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load budget")
		return
	}
	br := buildBudgetResponse(budget, expenses)

	// PR3 wires the operating-hours check behind ?check_hours=true; accepted
	// (and tolerantly parsed) now so the surface is stable.
	checkHours, _ := strconv.ParseBool(r.URL.Query().Get("check_hours"))

	findings := reviewTrip(data, reviewOptions{CheckHours: checkHours, Budget: &br})
	writeJSON(w, http.StatusOK, ReviewResponse{Findings: findings})
}
