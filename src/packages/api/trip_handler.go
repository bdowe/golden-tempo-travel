package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

const dateLayout = "2006-01-02"

// --- response / request types ---

type ItineraryItemResponse struct {
	ID          string  `json:"id"`
	Position    int     `json:"position"`
	Name        string  `json:"name"`
	PlaceID     *string `json:"place_id,omitempty"`
	Address     *string `json:"address,omitempty"`
	Latitude    float64 `json:"latitude"`
	Longitude   float64 `json:"longitude"`
	Category    *string `json:"category,omitempty"`
	TimeOfDay   *string `json:"time_of_day,omitempty"`
	City        *string `json:"city,omitempty"`
	DayTripFrom *string `json:"day_trip_from,omitempty"`
	Day         *int    `json:"day,omitempty"`
	// Local-source attribution snapshots (specs/add-to-itinerary): who
	// recommended this place and which pin it came from. Nullable, no FK —
	// they survive pin archival by design.
	LocalSourceName       *string `json:"local_source_name,omitempty"`
	LocalRecommendationID *string `json:"local_recommendation_id,omitempty"`
}

var allowedItemCategories = map[string]bool{"attraction": true, "restaurant": true}

var allowedTimesOfDay = map[string]bool{"morning": true, "afternoon": true, "evening": true}

type TripResponse struct {
	ID             string                  `json:"id"`
	Title          string                  `json:"title"`
	Summary        *string                 `json:"summary,omitempty"`
	StartDate      *string                 `json:"start_date,omitempty"`
	EndDate        *string                 `json:"end_date,omitempty"`
	Status         string                  `json:"status"`
	ChatID         *string                 `json:"chat_id,omitempty"`
	VersionCount   int                     `json:"version_count"`
	Cities         []string                `json:"cities,omitempty"`
	CreatedAt      time.Time               `json:"created_at"`
	UpdatedAt      time.Time               `json:"updated_at"`
	Items          []ItineraryItemResponse `json:"items,omitempty"`
	Accommodations []AccommodationResponse `json:"accommodations,omitempty"`
	Segments       []SegmentResponse       `json:"segments,omitempty"`
	BookingTodos   []BookingTodoResponse   `json:"booking_todos,omitempty"`
	// Access is "owner" or "editor" (collaborator). Absent on responses
	// that predate collaboration; clients treat missing as owner.
	Access    string  `json:"access,omitempty"`
	OwnerName *string `json:"owner_name,omitempty"` // set when access == "editor"
}

type PatchTripRequest struct {
	Title     *string `json:"title"`
	StartDate *string `json:"start_date"`
	EndDate   *string `json:"end_date"`
	Status    *string `json:"status"`
}

var allowedStatuses = map[string]bool{"draft": true, "planned": true}

// --- helpers ---

func dateToPtr(d pgtype.Date) *string {
	if !d.Valid {
		return nil
	}
	s := d.Time.Format(dateLayout)
	return &s
}

func int32PtrToIntPtr(p *int32) *int {
	if p == nil {
		return nil
	}
	v := int(*p)
	return &v
}

func pgUUIDToStringPtr(u pgtype.UUID) *string {
	if !u.Valid {
		return nil
	}
	s := uuid.UUID(u.Bytes).String()
	return &s
}

func toItineraryItemResponse(it store.ItineraryItem) ItineraryItemResponse {
	return ItineraryItemResponse{
		ID:                    it.ID.String(),
		Position:              int(it.Position),
		Name:                  it.Name,
		PlaceID:               it.PlaceID,
		Address:               it.Address,
		Latitude:              it.Latitude,
		Longitude:             it.Longitude,
		Category:              it.Category,
		TimeOfDay:             it.TimeOfDay,
		City:                  it.City,
		DayTripFrom:           it.DayTripFrom,
		Day:                   int32PtrToIntPtr(it.Day),
		LocalSourceName:       it.LocalSourceName,
		LocalRecommendationID: pgUUIDToStringPtr(it.LocalRecommendationID),
	}
}

func toTripResponse(t store.Trip, items []store.ItineraryItem, accommodations []store.Accommodation, segments []store.TripSegment, bookingTodos []store.BookingTodo) TripResponse {
	resp := TripResponse{
		ID:        t.ID.String(),
		Title:     t.Title,
		Summary:   t.Summary,
		StartDate: dateToPtr(t.StartDate),
		EndDate:   dateToPtr(t.EndDate),
		Status:    t.Status,
		ChatID:    t.ChatID,
		CreatedAt: t.CreatedAt,
		UpdatedAt: t.UpdatedAt,
	}
	for _, it := range items {
		resp.Items = append(resp.Items, toItineraryItemResponse(it))
	}
	for _, a := range accommodations {
		resp.Accommodations = append(resp.Accommodations, toAccommodationResponse(a))
	}
	for _, s := range segments {
		resp.Segments = append(resp.Segments, toSegmentResponse(s))
	}
	for _, bt := range bookingTodos {
		resp.BookingTodos = append(resp.BookingTodos, toBookingTodoResponse(bt))
	}
	return resp
}

// persistTrip saves a finalized itinerary as a Trip owned by userID, in a single
// transaction. Called from the agent's create_itinerary step for signed-in users.
// chatID stamps the trip with its conversation so My Trips can collapse repeated
// refinements to the latest version; an empty chatID is stored as NULL.
//
// newLineage reports whether this save started a brand-new trip lineage (as
// opposed to adding a version to an existing chat lineage). The caller uses
// it to gate the free-cap active_trips crossing signal, which a version save
// must never emit (specs/free-cap-instrumentation).
func persistTrip(ctx context.Context, userID uuid.UUID, chatID, title, summary, startDate, endDate string, locations []map[string]any) (tripID string, newLineage bool, err error) {
	tx, err := dbPool.Begin(ctx)
	if err != nil {
		return "", false, err
	}
	defer tx.Rollback(ctx)
	q := store.New(tx)

	summaryText := strings.TrimSpace(summary)
	finalTitle := strings.TrimSpace(title)
	if finalTitle == "" {
		// Fall back to the first line of the summary, then the first location.
		if summaryText != "" {
			finalTitle = strings.TrimSpace(strings.SplitN(summaryText, "\n", 2)[0])
		}
		if finalTitle == "" && len(locations) > 0 {
			if n, ok := locations[0]["name"].(string); ok && n != "" {
				finalTitle = "Trip to " + n
			}
		}
		if finalTitle == "" {
			finalTitle = "Untitled trip"
		}
	}

	var summaryPtr *string
	if summaryText != "" {
		summaryPtr = &summaryText
	}
	var chatPtr *string
	if c := strings.TrimSpace(chatID); c != "" {
		chatPtr = &c
	}

	// Detect new-lineage vs version save inside the same transaction as the
	// insert (a chat-less save always stands alone, i.e. a new lineage).
	// Fail-open: if the check errors, treat the lineage as existing so the
	// free-cap signal is skipped rather than over-emitted.
	newLineage = true
	if chatPtr != nil {
		exists, lerr := q.TripLineageExists(ctx, store.TripLineageExistsParams{UserID: userID, ChatID: chatPtr})
		switch {
		case lerr != nil:
			log.Printf("trip lineage check failed (treating as existing lineage): %v", lerr)
			newLineage = false
		case exists:
			newLineage = false
		}
	}

	trip, err := q.CreateTrip(ctx, store.CreateTripParams{UserID: userID, Title: finalTitle, Status: "draft", ChatID: chatPtr, Summary: summaryPtr})
	if err != nil {
		return "", false, err
	}

	maxDay := 1
	for i, loc := range locations {
		params := itemParamsFromLocation(trip.ID, int32(i), loc)
		if params.Day != nil && int(*params.Day) > maxDay {
			maxDay = int(*params.Day)
		}
		if _, err := q.CreateItineraryItem(ctx, params); err != nil {
			return "", false, err
		}
	}

	// Save the trip's date span when the agent supplied a start date. A missing
	// end date is derived from the start plus the itinerary's day span.
	if start := strings.TrimSpace(startDate); start != "" {
		end := strings.TrimSpace(endDate)
		if end == "" {
			if t, perr := time.Parse("2006-01-02", start); perr == nil {
				end = t.AddDate(0, 0, maxDay-1).Format("2006-01-02")
			}
		}
		startD, serr := parseDateParam(&start)
		endD, eerr := parseDateParam(&end)
		if serr == nil && eerr == nil {
			if _, err := q.UpdateTrip(ctx, store.UpdateTripParams{
				ID:        trip.ID,
				UserID:    userID,
				StartDate: startD,
				EndDate:   endD,
			}); err != nil {
				return "", false, err
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return "", false, err
	}
	return trip.ID.String(), newLineage, nil
}

func tripIDFromPath(r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(mux.Vars(r)["id"])
	if err != nil {
		return uuid.UUID{}, false
	}
	return id, true
}

// --- handlers (all behind authMiddleware) ---

// listTripsHandler returns one trip per chat group (the latest version), each
// carrying version_count so admins can surface the older versions.
func listTripsHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	trips, err := store.New(dbPool).ListLatestTripsByOwner(r.Context(), user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load trips")
		return
	}
	out := make([]TripResponse, 0, len(trips))
	for _, t := range trips {
		resp := toTripResponse(store.Trip{
			ID:        t.ID,
			UserID:    t.UserID,
			CreatedAt: t.CreatedAt,
			UpdatedAt: t.UpdatedAt,
			Title:     t.Title,
			StartDate: t.StartDate,
			EndDate:   t.EndDate,
			Status:    t.Status,
			ChatID:    t.ChatID,
		}, nil, nil, nil, nil)
		resp.VersionCount = int(t.VersionCount)
		resp.Cities = t.Cities
		out = append(out, resp)
	}
	writeJSON(w, http.StatusOK, out)
}

// listTripVersionsHandler returns every trip in a chat group (newest first).
// Admin-only — registered behind adminMiddleware; used to inspect the
// itinerary versions a single chat produced.
func listTripVersionsHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	chatID := strings.TrimSpace(r.URL.Query().Get("chat_id"))
	if chatID == "" {
		writeJSONError(w, http.StatusBadRequest, "chat_id is required")
		return
	}
	trips, err := store.New(dbPool).ListTripVersionsByChat(r.Context(), store.ListTripVersionsByChatParams{
		UserID: user.ID, ChatID: &chatID,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load trip versions")
		return
	}
	out := make([]TripResponse, 0, len(trips))
	for _, t := range trips {
		out = append(out, toTripResponse(t, nil, nil, nil, nil))
	}
	writeJSON(w, http.StatusOK, out)
}

func getTripHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	// Owner or editor-collaborator may read; v1 has no viewer membership, so
	// editable == viewable.
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	q := store.New(dbPool)
	items, err := q.GetItineraryItemsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	accommodations, err := q.ListAccommodationsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load accommodations")
		return
	}
	segments, err := q.ListSegmentsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load segments")
		return
	}
	bookingTodos, err := q.ListBookingTodosByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load booking todos")
		return
	}
	resp := toTripResponse(trip, items, accommodations, segments, bookingTodos)
	if trip.UserID == user.ID {
		resp.Access = "owner"
	} else {
		resp.Access = "editor"
		if owner, err := q.GetUserByID(r.Context(), trip.UserID); err == nil &&
			owner.DisplayName != nil && *owner.DisplayName != "" {
			resp.OwnerName = owner.DisplayName
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

// refineTripHandler returns the chat_id to reopen a saved trip in the AI agent,
// assigning one to legacy (NULL chat_id) trips so the agent's new itineraries
// append as versions of this same trip instead of spawning a duplicate card.
func refineTripHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	id, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	q := store.New(dbPool)
	trip, err := q.GetTripByIDAndOwner(r.Context(), store.GetTripByIDAndOwnerParams{ID: id, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}

	chatID := trip.ChatID
	if chatID == nil {
		token, err := generateSessionToken()
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not start refine session")
			return
		}
		newID := "chat-" + token
		updated, err := q.UpdateTrip(r.Context(), store.UpdateTripParams{
			ChatID: &newID, ID: id, UserID: user.ID,
		})
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not start refine session")
			return
		}
		chatID = updated.ChatID
	}

	writeJSON(w, http.StatusOK, map[string]string{"chat_id": *chatID})
}

func patchTripHandler(w http.ResponseWriter, r *http.Request) {
	// Editors may adjust title/dates/status too. UpdateTrip's WHERE user_id
	// stays owner-scoped — satisfied by the OWNER's id off the authorized row.
	authorized, ok := editableTrip(w, r)
	if !ok {
		return
	}
	id := authorized.ID
	var req PatchTripRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	if req.Status != nil && !allowedStatuses[*req.Status] {
		writeJSONError(w, http.StatusBadRequest, "status must be 'draft' or 'planned'")
		return
	}

	start, err := parseDateParam(req.StartDate)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "start_date must be YYYY-MM-DD")
		return
	}
	end, err := parseDateParam(req.EndDate)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "end_date must be YYYY-MM-DD")
		return
	}
	if start.Valid && end.Valid && end.Time.Before(start.Time) {
		writeJSONError(w, http.StatusBadRequest, "end_date must not be before start_date")
		return
	}

	q := store.New(dbPool)
	trip, err := q.UpdateTrip(r.Context(), store.UpdateTripParams{
		Title:     req.Title,
		StartDate: start,
		EndDate:   end,
		Status:    req.Status,
		ID:        id,
		UserID:    authorized.UserID,
	})
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not update trip")
		return
	}
	items, err := q.GetItineraryItemsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	writeJSON(w, http.StatusOK, toTripResponse(trip, items, nil, nil, nil))
}

func deleteTripHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	id, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	rows, err := store.New(dbPool).DeleteTrip(r.Context(), store.DeleteTripParams{ID: id, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete trip")
		return
	}
	if rows == 0 {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// parseDateParam turns an optional "YYYY-MM-DD" string into a pgtype.Date.
// A nil input yields an invalid (NULL) date, which UpdateTrip's COALESCE leaves unchanged.
func parseDateParam(s *string) (pgtype.Date, error) {
	if s == nil || strings.TrimSpace(*s) == "" {
		return pgtype.Date{}, nil
	}
	t, err := time.Parse(dateLayout, *s)
	if err != nil {
		return pgtype.Date{}, err
	}
	return pgtype.Date{Time: t, Valid: true}, nil
}
