package main

import (
	"context"
	"net/http"
	"time"

	"github.com/google/uuid"

	"travel-route-planner/store"
)

// Owner-private trip export. The authed owner (or an editor collaborator) mints
// a short-lived signed token via POST /trips/{id}/export-token; the two public,
// token-gated GET routes (print.html, calendar.ics) verify it and render the
// FULL trip — drafts, booking todos, and packing checklist included. This is
// deliberately NOT the redacted public share view: export is for the trip's own
// planners, printing or importing their complete plan.

type ExportTokenResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

// exportTokenHandler mints a signed export token for a trip. Gated by
// editableTrip (owner or active editor-collaborator), matching every other
// trip mutation. The token embeds the trip id + expiry and is self-verifying,
// so the public export GETs need no session.
func exportTokenHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	token, exp := newExportToken(trip.ID)
	writeJSON(w, http.StatusOK, ExportTokenResponse{Token: token, ExpiresAt: exp})
}

// exportData is the full owner-view snapshot rendered by both export formats.
type exportData struct {
	Trip           store.Trip
	Items          []store.ItineraryItem
	Accommodations []store.Accommodation
	Segments       []store.TripSegment
	BookingTodos   []store.BookingTodo
	Checklist      []store.TripChecklistItem
}

// loadExportData loads the full trip by id — no owner scoping, because the
// verified export token IS the authorization. Unlike buildSharedTripResponse it
// loads ALL accommodations/segments (drafts included) plus booking todos and
// the packing checklist. A missing trip returns ok=false so callers 404.
func loadExportData(ctx context.Context, tripID uuid.UUID) (exportData, bool) {
	if dbPool == nil {
		return exportData{}, false
	}
	q := store.New(dbPool)
	// GetTripForUpdate is the only by-id-alone trip read; in autocommit its
	// row lock is a momentary single-statement hold, harmless for this read.
	trip, err := q.GetTripForUpdate(ctx, tripID)
	if err != nil {
		return exportData{}, false
	}
	items, err := q.GetItineraryItemsByTrip(ctx, tripID)
	if err != nil {
		return exportData{}, false
	}
	accommodations, err := q.ListAccommodationsByTrip(ctx, tripID)
	if err != nil {
		return exportData{}, false
	}
	segments, err := q.ListSegmentsByTrip(ctx, tripID)
	if err != nil {
		return exportData{}, false
	}
	todos, err := q.ListBookingTodosByTrip(ctx, tripID)
	if err != nil {
		return exportData{}, false
	}
	checklist, err := q.ListChecklistItemsByTrip(ctx, tripID)
	if err != nil {
		return exportData{}, false
	}
	return exportData{
		Trip:           trip,
		Items:          items,
		Accommodations: accommodations,
		Segments:       segments,
		BookingTodos:   todos,
		Checklist:      checklist,
	}, true
}

// resolveExport turns the {token} path var into loaded export data. A bad or
// expired token, or a vanished trip, both yield ok=false — the caller answers a
// single opaque 404 either way so nothing about the trip leaks.
func resolveExport(r *http.Request, token string) (exportData, bool) {
	tripID, ok := verifyExportToken(token)
	if !ok {
		return exportData{}, false
	}
	return loadExportData(r.Context(), tripID)
}
