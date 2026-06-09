package main

import (
	"context"
	"encoding/json"
	"errors"
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
		resp.Items = append(resp.Items, ItineraryItemResponse{
			ID:          it.ID.String(),
			Position:    int(it.Position),
			Name:        it.Name,
			PlaceID:     it.PlaceID,
			Address:     it.Address,
			Latitude:    it.Latitude,
			Longitude:   it.Longitude,
			Category:    it.Category,
			TimeOfDay:   it.TimeOfDay,
			City:        it.City,
			DayTripFrom: it.DayTripFrom,
		})
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
func persistTrip(ctx context.Context, userID uuid.UUID, chatID, title, summary string, locations []map[string]any) (string, error) {
	tx, err := dbPool.Begin(ctx)
	if err != nil {
		return "", err
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
	trip, err := q.CreateTrip(ctx, store.CreateTripParams{UserID: userID, Title: finalTitle, Status: "draft", ChatID: chatPtr, Summary: summaryPtr})
	if err != nil {
		return "", err
	}

	for i, loc := range locations {
		name, _ := loc["name"].(string)
		lat, _ := loc["latitude"].(float64)
		lng, _ := loc["longitude"].(float64)
		var placeID, address, city, dayTripFrom, category, timeOfDay *string
		if s, ok := loc["place_id"].(string); ok && s != "" {
			placeID = &s
		}
		if s, ok := loc["address"].(string); ok && s != "" {
			address = &s
		}
		if s, ok := loc["city"].(string); ok {
			c := strings.TrimSpace(s)
			if c != "" {
				city = &c
			}
		}
		if s, ok := loc["day_trip_from"].(string); ok {
			d := strings.TrimSpace(s)
			if d != "" {
				dayTripFrom = &d
			}
		}
		if s, ok := loc["category"].(string); ok {
			c := strings.ToLower(strings.TrimSpace(s))
			if allowedItemCategories[c] {
				category = &c
			}
		}
		if s, ok := loc["time_of_day"].(string); ok {
			t := strings.ToLower(strings.TrimSpace(s))
			if allowedTimesOfDay[t] {
				timeOfDay = &t
			}
		}
		if _, err := q.CreateItineraryItem(ctx, store.CreateItineraryItemParams{
			TripID:      trip.ID,
			Position:    int32(i),
			Name:        name,
			PlaceID:     placeID,
			Address:     address,
			Latitude:    lat,
			Longitude:   lng,
			Category:    category,
			TimeOfDay:   timeOfDay,
			City:        city,
			DayTripFrom: dayTripFrom,
		}); err != nil {
			return "", err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return trip.ID.String(), nil
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
// Admin-only — used to inspect the itinerary versions a single chat produced.
func listTripVersionsHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	if !user.IsAdmin {
		writeJSONError(w, http.StatusForbidden, "admin access required")
		return
	}
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
	writeJSON(w, http.StatusOK, toTripResponse(trip, items, accommodations, segments, bookingTodos))
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
	user, _ := userFromContext(r.Context())
	id, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
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
		UserID:    user.ID,
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
