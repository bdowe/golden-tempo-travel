package main

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"

	anthropic "github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"
	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// local_ingest_handler.go is the admin-only curation backend for local-sourced
// content. All routes here sit behind authMiddleware + adminMiddleware.

// --- local sources -----------------------------------------------------------

type createLocalSourceRequest struct {
	Name        string `json:"name"`
	Bio         string `json:"bio"`
	PhotoURL    string `json:"photo_url"`
	Location    string `json:"location"`
	Expertise   string `json:"expertise"`
	Credibility string `json:"credibility"`
	ConsentRef  string `json:"consent_ref"`
}

func createLocalSourceHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var req createLocalSourceRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		writeJSONError(w, http.StatusUnprocessableEntity, "name is required")
		return
	}
	src, err := store.New(dbPool).CreateLocalSource(r.Context(), store.CreateLocalSourceParams{
		Name:        strings.TrimSpace(req.Name),
		Bio:         strPtrOrNil(req.Bio),
		PhotoUrl:    strPtrOrNil(req.PhotoURL),
		Location:    strPtrOrNil(req.Location),
		Expertise:   strPtrOrNil(req.Expertise),
		Credibility: strPtrOrNil(req.Credibility),
		ConsentRef:  strPtrOrNil(req.ConsentRef),
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not create local source")
		return
	}
	writeJSON(w, http.StatusCreated, src)
}

func listLocalSourcesHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	sources, err := store.New(dbPool).ListLocalSources(r.Context())
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not list sources")
		return
	}
	if sources == nil {
		sources = []store.LocalSource{}
	}
	writeJSON(w, http.StatusOK, sources)
}

// --- ingestion ---------------------------------------------------------------

type ingestRequest struct {
	SourceID string `json:"source_id"`
	City     string `json:"city"`
	Kind     string `json:"kind"` // transcript | notes | voice_memo
	RawText  string `json:"raw_text"`
}

type ingestResponse struct {
	Recommendations []store.LocalRecommendation `json:"recommendations"`
	GuideID         *string                     `json:"guide_id,omitempty"`
	Verified        int                         `json:"verified"`
	Unverified      int                         `json:"unverified"`
}

// ingestLocalHandler: persist raw material, run AI extraction, verify each pin
// against Google Places to fill coordinates, and insert everything as drafts.
func ingestLocalHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var req ingestRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	sourceID, err := uuid.Parse(strings.TrimSpace(req.SourceID))
	if err != nil {
		writeJSONError(w, http.StatusUnprocessableEntity, "valid source_id is required")
		return
	}
	city := strings.TrimSpace(req.City)
	if city == "" || strings.TrimSpace(req.RawText) == "" {
		writeJSONError(w, http.StatusUnprocessableEntity, "city and raw_text are required")
		return
	}
	kind := strings.TrimSpace(req.Kind)
	if kind == "" {
		kind = "notes"
	}

	apiKey := os.Getenv("ANTHROPIC_API_KEY")
	if apiKey == "" {
		writeJSONError(w, http.StatusServiceUnavailable, "ANTHROPIC_API_KEY not configured")
		return
	}

	q := store.New(dbPool)

	// Confirm the source exists before doing any work / attributing anything.
	if _, err := q.GetLocalSource(r.Context(), sourceID); err != nil {
		writeJSONError(w, http.StatusUnprocessableEntity, "unknown source_id")
		return
	}

	// 1. Provenance first — record the raw material before extraction.
	if _, err := q.CreateSourceMaterial(r.Context(), store.CreateSourceMaterialParams{
		SourceID: sourceID,
		Kind:     kind,
		RawText:  req.RawText,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save source material")
		return
	}

	// 2. Extract structured drafts.
	client := anthropic.NewClient(option.WithAPIKey(apiKey))
	content, err := extractLocalContent(r.Context(), client, city, req.RawText)
	if err != nil {
		writeJSONError(w, http.StatusBadGateway, "extraction failed: "+err.Error())
		return
	}

	// 3. Verify + insert each recommendation.
	places := NewGooglePlacesService()
	resp := ingestResponse{Recommendations: []store.LocalRecommendation{}}
	var recIDs []uuid.UUID
	for _, rec := range content.Recommendations {
		name := strings.TrimSpace(rec.Name)
		if name == "" {
			continue
		}
		params := store.CreateLocalRecommendationParams{
			SourceID:     sourceID,
			City:         city,
			Neighborhood: strPtrOrNil(rec.Neighborhood),
			Name:         name,
			Category:     strPtrOrNil(rec.Category),
			Tip:          strPtrOrNil(rec.Tip),
			Quote:        strPtrOrNil(rec.Quote),
			Tags:         normalizeInterests(rec.Tags), // trims + dedupes; reused helper
			Status:       "draft",
		}
		// Anti-hallucination: resolve the place on Google. Unmatched pins are kept
		// as unverified drafts (curator can fix the name) — never silently dropped.
		if hits, perr := places.SearchPlaces(placeQuery(rec.SearchHint, name, city)); perr == nil && len(hits) > 0 {
			hit := hits[0]
			params.PlaceID = strPtrOrNil(hit.PlaceID)
			params.Address = strPtrOrNil(hit.Address)
			lat, lng := hit.Latitude, hit.Longitude
			params.Latitude = &lat
			params.Longitude = &lng
			params.PlaceVerified = true
			resp.Verified++
		} else {
			resp.Unverified++
		}
		saved, err := q.CreateLocalRecommendation(r.Context(), params)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not save recommendation")
			return
		}
		resp.Recommendations = append(resp.Recommendations, saved)
		recIDs = append(recIDs, saved.ID)
	}

	// 4. Optional narrative guide, linking the pins in order.
	if content.Guide != nil && strings.TrimSpace(content.Guide.Title) != "" && strings.TrimSpace(content.Guide.Body) != "" {
		guide, err := q.CreateLocalGuide(r.Context(), store.CreateLocalGuideParams{
			SourceID:     sourceID,
			Title:        strings.TrimSpace(content.Guide.Title),
			City:         city,
			Neighborhood: strPtrOrNil(content.Guide.Neighborhood),
			Body:         content.Guide.Body,
			Status:       "draft",
		})
		if err == nil {
			for i, id := range recIDs {
				_ = q.LinkGuideRecommendation(r.Context(), store.LinkGuideRecommendationParams{
					GuideID: guide.ID, RecommendationID: id, Position: int32(i),
				})
			}
			gid := guide.ID.String()
			resp.GuideID = &gid
		}
	}

	writeJSON(w, http.StatusCreated, resp)
}

// placeQuery builds the Google Places text-search string, preferring the model's
// search hint and always appending the city for disambiguation.
func placeQuery(hint, name, city string) string {
	base := strings.TrimSpace(hint)
	if base == "" {
		base = name
	}
	if !strings.Contains(strings.ToLower(base), strings.ToLower(city)) {
		base = base + ", " + city
	}
	return base
}

// --- draft review / edit / publish ------------------------------------------

func listRecommendationsByStatusHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	status := r.URL.Query().Get("status")
	if status == "" {
		status = "draft"
	}
	rows, err := store.New(dbPool).ListRecommendationsByStatus(r.Context(), status)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not list recommendations")
		return
	}
	if rows == nil {
		rows = []store.ListRecommendationsByStatusRow{}
	}
	writeJSON(w, http.StatusOK, rows)
}

type updateRecommendationRequest struct {
	City         *string  `json:"city"`
	Neighborhood *string  `json:"neighborhood"`
	Name         *string  `json:"name"`
	PlaceID      *string  `json:"place_id"`
	Address      *string  `json:"address"`
	Latitude     *float64 `json:"latitude"`
	Longitude    *float64 `json:"longitude"`
	Category     *string  `json:"category"`
	Tip          *string  `json:"tip"`
	Quote        *string  `json:"quote"`
}

func updateRecommendationHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	id, err := uuid.Parse(mux.Vars(r)["id"])
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}
	var req updateRecommendationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	// When a curator supplies coordinates by hand, mark the place verified.
	var verified *bool
	if req.Latitude != nil && req.Longitude != nil {
		t := true
		verified = &t
	}
	rec, err := store.New(dbPool).UpdateLocalRecommendation(r.Context(), store.UpdateLocalRecommendationParams{
		ID:            id,
		City:          req.City,
		Neighborhood:  req.Neighborhood,
		Name:          req.Name,
		PlaceID:       req.PlaceID,
		Address:       req.Address,
		Latitude:      req.Latitude,
		Longitude:     req.Longitude,
		Category:      req.Category,
		Tip:           req.Tip,
		Quote:         req.Quote,
		PlaceVerified: verified,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not update recommendation")
		return
	}
	writeJSON(w, http.StatusOK, rec)
}

// publishRecommendationHandler flips a draft to published, but refuses to publish
// a pin with no coordinates (an unverified place could be a hallucination).
func publishRecommendationHandler(w http.ResponseWriter, r *http.Request) {
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
	rec, err := q.GetLocalRecommendation(r.Context(), id)
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "recommendation not found")
		return
	}
	if rec.Latitude == nil || rec.Longitude == nil {
		writeJSONError(w, http.StatusUnprocessableEntity, "cannot publish: place not verified (no coordinates)")
		return
	}
	updated, err := q.SetLocalRecommendationStatus(r.Context(), store.SetLocalRecommendationStatusParams{
		ID: id, Status: "published",
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not publish")
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

// --- coverage ----------------------------------------------------------------

type coverageRow struct {
	City      string `json:"city"`
	Published int64  `json:"published"`
	Draft     int64  `json:"draft"`
	Archived  int64  `json:"archived"`
}

func localCoverageHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	rows, err := store.New(dbPool).CountRecommendationsByCityStatus(r.Context())
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not compute coverage")
		return
	}
	byCity := map[string]*coverageRow{}
	var order []string
	for _, row := range rows {
		c := byCity[row.City]
		if c == nil {
			c = &coverageRow{City: row.City}
			byCity[row.City] = c
			order = append(order, row.City)
		}
		switch row.Status {
		case "published":
			c.Published = row.N
		case "draft":
			c.Draft = row.N
		case "archived":
			c.Archived = row.N
		}
	}
	out := make([]coverageRow, 0, len(order))
	for _, c := range order {
		out = append(out, *byCity[c])
	}
	writeJSON(w, http.StatusOK, out)
}
