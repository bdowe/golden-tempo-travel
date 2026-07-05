package main

import (
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// local_public_handler.go exposes published local-sourced content to travelers.
// These endpoints are unauthenticated (public reads); only 'published' rows are
// ever returned (enforced in the SQL), so drafts never leak.

// GET /api/v1/local/recommendations?city=
func localRecommendationsHandler(w http.ResponseWriter, r *http.Request) {
	city := strings.TrimSpace(r.URL.Query().Get("city"))
	if city == "" {
		writeJSONError(w, http.StatusBadRequest, "city is required")
		return
	}
	category := strings.TrimSpace(r.URL.Query().Get("category"))
	recs, err := localRecsService.SearchByCity(r.Context(), city, category)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load recommendations")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"city": city, "recommendations": recs})
}

// maxDiscoverGuides caps the cross-city guide list served when no ?city=
// filter is given (the home-screen discover row).
const maxDiscoverGuides = 20

// GET /api/v1/local/guides?city=
// city is optional: when present, returns that city's published guides; when
// blank, returns the newest published guides across all cities (capped).
func localGuidesHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSON(w, http.StatusOK, map[string]any{"city": "", "guides": []any{}})
		return
	}
	city := strings.TrimSpace(r.URL.Query().Get("city"))
	if city == "" {
		guides, err := store.New(dbPool).ListPublishedGuides(r.Context(), maxDiscoverGuides)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not load guides")
			return
		}
		if guides == nil {
			guides = []store.ListPublishedGuidesRow{}
		}
		writeJSON(w, http.StatusOK, map[string]any{"city": "", "guides": guides})
		return
	}
	guides, err := store.New(dbPool).ListPublishedGuidesByCity(r.Context(), city)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load guides")
		return
	}
	if guides == nil {
		guides = []store.ListPublishedGuidesByCityRow{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"city": city, "guides": guides})
}

// GET /api/v1/local/guides/{id} — the guide plus its ordered published pins.
func localGuideDetailHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	id, err := uuid.Parse(mux.Vars(r)["id"])
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}
	q := store.New(dbPool)
	guide, err := q.GetLocalGuide(r.Context(), id)
	if err != nil || guide.Status != "published" {
		writeJSONError(w, http.StatusNotFound, "guide not found")
		return
	}
	rows, err := q.ListRecommendationsByGuide(r.Context(), id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load guide items")
		return
	}
	if rows == nil {
		rows = []store.ListRecommendationsByGuideRow{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"guide": guide, "recommendations": rows})
}
