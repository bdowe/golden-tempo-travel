package main

import (
	"encoding/json"
	"net/http"
	"strings"

	"travel-route-planner/store"
)

// DraftStay / DraftTransport are the itinerary-derived booking drafts sent by
// the client's sync (the same client pass that derives the booking-todo
// checklist). They land in accommodations / trip_segments as auto=true rows.
type DraftStay struct {
	AutoKey  string  `json:"auto_key"` // stay:<city>
	Name     string  `json:"name"`
	Address  *string `json:"address"`
	CheckIn  *string `json:"check_in"`
	CheckOut *string `json:"check_out"`
}

type DraftTransport struct {
	AutoKey     string  `json:"auto_key"` // transport:<a>>><b>
	Mode        string  `json:"mode"`
	Origin      *string `json:"origin"`
	Destination *string `json:"destination"`
	DepartDate  *string `json:"depart_date"`
}

type SyncBookingDraftsRequest struct {
	Stays      []DraftStay      `json:"stays"`
	Transports []DraftTransport `json:"transports"`
}

// syncBookingDraftsHandler upserts the client's itinerary-derived draft stays
// and transport segments and prunes drafts whose legs no longer exist.
// Confirmed rows (auto=false) and dismissed tombstones are never modified by
// the upsert; the prune only ever deletes auto=true rows. Returns the fresh
// (dismissed-filtered) lists.
// (Like syncBookingTodosHandler, this must NEVER TouchTrip: it runs on every
// trip load and would otherwise stamp freshness/attribution passively.)
func syncBookingDraftsHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	tripID := trip.ID
	var req SyncBookingDraftsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	q := store.New(dbPool)

	stayKeys := make([]string, 0, len(req.Stays))
	for _, s := range req.Stays {
		if !strings.HasPrefix(s.AutoKey, "stay:") || strings.TrimSpace(s.Name) == "" {
			writeJSONError(w, http.StatusBadRequest, "each stay needs a stay: auto_key and a name")
			return
		}
		checkIn, err := parseDateParam(s.CheckIn)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "check_in must be YYYY-MM-DD")
			return
		}
		checkOut, err := parseDateParam(s.CheckOut)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "check_out must be YYYY-MM-DD")
			return
		}
		key := s.AutoKey
		if _, err := q.UpsertDraftAccommodation(r.Context(), store.UpsertDraftAccommodationParams{
			TripID:   tripID,
			Name:     strings.TrimSpace(s.Name),
			Address:  s.Address,
			CheckIn:  checkIn,
			CheckOut: checkOut,
			AutoKey:  &key,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not save draft stay")
			return
		}
		stayKeys = append(stayKeys, key)
	}

	transportKeys := make([]string, 0, len(req.Transports))
	for _, t := range req.Transports {
		mode := strings.ToLower(strings.TrimSpace(t.Mode))
		if !strings.HasPrefix(t.AutoKey, "transport:") || !allowedSegmentModes[mode] {
			writeJSONError(w, http.StatusBadRequest, "each transport needs a transport: auto_key and a valid mode")
			return
		}
		depart, err := parseDateParam(t.DepartDate)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "depart_date must be YYYY-MM-DD")
			return
		}
		key := t.AutoKey
		if _, err := q.UpsertDraftSegment(r.Context(), store.UpsertDraftSegmentParams{
			TripID:      tripID,
			Mode:        mode,
			Origin:      t.Origin,
			Destination: t.Destination,
			DepartDate:  depart,
			AutoKey:     &key,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not save draft transport")
			return
		}
		transportKeys = append(transportKeys, key)
	}

	if _, err := q.DeleteStaleDraftAccommodations(r.Context(), store.DeleteStaleDraftAccommodationsParams{
		TripID: tripID,
		Keys:   stayKeys,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not prune draft stays")
		return
	}
	if _, err := q.DeleteStaleDraftSegments(r.Context(), store.DeleteStaleDraftSegmentsParams{
		TripID: tripID,
		Keys:   transportKeys,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not prune draft transports")
		return
	}

	accommodations, err := q.ListAccommodationsByTrip(r.Context(), tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load accommodations")
		return
	}
	segments, err := q.ListSegmentsByTrip(r.Context(), tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load segments")
		return
	}
	accResp := make([]AccommodationResponse, 0, len(accommodations))
	for _, a := range accommodations {
		accResp = append(accResp, toAccommodationResponse(a))
	}
	segResp := make([]SegmentResponse, 0, len(segments))
	for _, s := range segments {
		segResp = append(segResp, toSegmentResponse(s))
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"accommodations": accResp,
		"segments":       segResp,
	})
}
