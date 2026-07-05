package main

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

type AddItineraryItemRequest struct {
	Name        string   `json:"name"`
	PlaceID     *string  `json:"place_id"`
	Address     *string  `json:"address"`
	Latitude    *float64 `json:"latitude"`
	Longitude   *float64 `json:"longitude"`
	Category    *string  `json:"category"`
	TimeOfDay   *string  `json:"time_of_day"`
	City        *string  `json:"city"`
	DayTripFrom *string  `json:"day_trip_from"`
	Day         *int     `json:"day"`
}

// insertPositionForDay places a new item at the end of its day: just after the
// last item whose day is set and <= the requested day. Unscheduled items (nil
// day) don't advance the cursor, so a day-tagged insert lands before the
// trailing unscheduled block. A nil requested day appends to the very end.
func insertPositionForDay(items []store.ItineraryItem, day *int) int {
	if day == nil {
		return len(items)
	}
	pos := 0
	for i, it := range items {
		if it.Day != nil && int(*it.Day) <= *day {
			pos = i + 1
		}
	}
	return pos
}

func addItineraryItemHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	var req AddItineraryItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		writeJSONError(w, http.StatusBadRequest, "name is required")
		return
	}
	var category *string
	if req.Category != nil {
		c := strings.ToLower(strings.TrimSpace(*req.Category))
		if !allowedItemCategories[c] {
			writeJSONError(w, http.StatusBadRequest, "category must be 'attraction' or 'restaurant'")
			return
		}
		category = &c
	}
	var timeOfDay *string
	if req.TimeOfDay != nil {
		t := strings.ToLower(strings.TrimSpace(*req.TimeOfDay))
		if !allowedTimesOfDay[t] {
			writeJSONError(w, http.StatusBadRequest, "time_of_day must be 'morning', 'afternoon' or 'evening'")
			return
		}
		timeOfDay = &t
	}
	var day *int32
	if req.Day != nil {
		if *req.Day < 1 {
			writeJSONError(w, http.StatusBadRequest, "day must be >= 1")
			return
		}
		d := int32(*req.Day)
		day = &d
	}
	var city *string
	if req.City != nil {
		if c := strings.TrimSpace(*req.City); c != "" {
			city = &c
		}
	}
	var dayTripFrom *string
	if req.DayTripFrom != nil {
		if d := strings.TrimSpace(*req.DayTripFrom); d != "" {
			dayTripFrom = &d
		}
	}
	// Columns are NOT NULL; (0,0) is the established "no location" sentinel the
	// app already excludes from the map and travel times.
	var lat, lng float64
	if req.Latitude != nil && req.Longitude != nil {
		lat, lng = *req.Latitude, *req.Longitude
	}

	ctx := r.Context()
	tx, err := dbPool.Begin(ctx)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save place")
		return
	}
	defer tx.Rollback(ctx)
	q := store.New(tx)

	items, err := q.GetItineraryItemsByTrip(ctx, tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	pos := insertPositionForDay(items, req.Day)
	if err := q.ShiftItineraryItemPositions(ctx, store.ShiftItineraryItemPositionsParams{
		TripID: tripID, Position: int32(pos),
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save place")
		return
	}
	if _, err := q.CreateItineraryItem(ctx, store.CreateItineraryItemParams{
		TripID:      tripID,
		Position:    int32(pos),
		Name:        name,
		PlaceID:     req.PlaceID,
		Address:     req.Address,
		Latitude:    lat,
		Longitude:   lng,
		Category:    category,
		TimeOfDay:   timeOfDay,
		City:        city,
		DayTripFrom: dayTripFrom,
		Day:         day,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save place")
		return
	}
	if err := q.TouchTrip(ctx, tripID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save place")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save place")
		return
	}

	user, _ := userFromContext(ctx)
	qr := store.New(dbPool)
	trip, err := qr.GetTripByIDAndOwner(ctx, store.GetTripByIDAndOwnerParams{ID: tripID, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load trip")
		return
	}
	updated, err := qr.GetItineraryItemsByTrip(ctx, tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	writeJSON(w, http.StatusCreated, toTripResponse(trip, updated, nil, nil, nil))
}

// itemIDFromPath parses the {itemId} path variable.
func itemIDFromPath(r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(mux.Vars(r)["itemId"])
	if err != nil {
		return uuid.UUID{}, false
	}
	return id, true
}

// UpdateItineraryItemRequest mirrors AddItineraryItemRequest with every field
// optional (COALESCE partial update — absent fields keep their value).
type UpdateItineraryItemRequest struct {
	Name        *string  `json:"name"`
	PlaceID     *string  `json:"place_id"`
	Address     *string  `json:"address"`
	Latitude    *float64 `json:"latitude"`
	Longitude   *float64 `json:"longitude"`
	Category    *string  `json:"category"`
	TimeOfDay   *string  `json:"time_of_day"`
	City        *string  `json:"city"`
	DayTripFrom *string  `json:"day_trip_from"`
	Day         *int     `json:"day"`
}

func patchItineraryItemHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	itemID, ok := itemIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "item not found")
		return
	}
	var req UpdateItineraryItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	params := store.UpdateItineraryItemParams{ID: itemID, TripID: tripID}
	if req.Name != nil {
		n := strings.TrimSpace(*req.Name)
		if n == "" {
			writeJSONError(w, http.StatusBadRequest, "name cannot be empty")
			return
		}
		params.Name = &n
	}
	if req.Category != nil {
		c := strings.ToLower(strings.TrimSpace(*req.Category))
		if !allowedItemCategories[c] {
			writeJSONError(w, http.StatusBadRequest, "category must be 'attraction' or 'restaurant'")
			return
		}
		params.Category = &c
	}
	if req.TimeOfDay != nil {
		t := strings.ToLower(strings.TrimSpace(*req.TimeOfDay))
		if !allowedTimesOfDay[t] {
			writeJSONError(w, http.StatusBadRequest, "time_of_day must be 'morning', 'afternoon' or 'evening'")
			return
		}
		params.TimeOfDay = &t
	}
	if req.Day != nil {
		if *req.Day < 1 {
			writeJSONError(w, http.StatusBadRequest, "day must be >= 1")
			return
		}
		d := int32(*req.Day)
		params.Day = &d
	}
	if req.City != nil {
		if c := strings.TrimSpace(*req.City); c != "" {
			params.City = &c
		}
	}
	if req.DayTripFrom != nil {
		if d := strings.TrimSpace(*req.DayTripFrom); d != "" {
			params.DayTripFrom = &d
		}
	}
	params.PlaceID = req.PlaceID
	params.Address = req.Address
	params.Latitude = req.Latitude
	params.Longitude = req.Longitude

	ctx := r.Context()
	item, err := store.New(dbPool).UpdateItineraryItem(ctx, params)
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "item not found")
		return
	}
	if err := store.New(dbPool).TouchTrip(ctx, tripID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save place")
		return
	}
	writeJSON(w, http.StatusOK, ItineraryItemResponse{
		ID:          item.ID.String(),
		Position:    int(item.Position),
		Name:        item.Name,
		PlaceID:     item.PlaceID,
		Address:     item.Address,
		Latitude:    item.Latitude,
		Longitude:   item.Longitude,
		Category:    item.Category,
		TimeOfDay:   item.TimeOfDay,
		City:        item.City,
		DayTripFrom: item.DayTripFrom,
		Day:         int32PtrToIntPtr(item.Day),
	})
}

func deleteItineraryItemHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	itemID, ok := itemIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "item not found")
		return
	}

	ctx := r.Context()
	tx, err := dbPool.Begin(ctx)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete place")
		return
	}
	defer tx.Rollback(ctx)
	q := store.New(tx)

	// Fetch first so we know which position gap to close.
	items, err := q.GetItineraryItemsByTrip(ctx, tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	var deletedPos int32 = -1
	for _, it := range items {
		if it.ID == itemID {
			deletedPos = it.Position
			break
		}
	}
	if deletedPos < 0 {
		writeJSONError(w, http.StatusNotFound, "item not found")
		return
	}
	if _, err := q.DeleteItineraryItem(ctx, store.DeleteItineraryItemParams{ID: itemID, TripID: tripID}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete place")
		return
	}
	if err := q.CloseItineraryItemPositionGap(ctx, store.CloseItineraryItemPositionGapParams{
		TripID: tripID, Position: deletedPos,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete place")
		return
	}
	if err := q.TouchTrip(ctx, tripID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete place")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete place")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type ReorderItineraryItemsRequest struct {
	ItemIDs []string `json:"item_ids"`
}

// reorderItineraryItemsHandler reassigns positions 0..n-1 to the submitted
// full-trip ordering. The id list must be exactly the trip's item set — the
// server accepts any full-trip permutation (the UI only submits within-day
// moves today, but the contract is future-proof).
func reorderItineraryItemsHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	var req ReorderItineraryItemsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	ctx := r.Context()
	tx, err := dbPool.Begin(ctx)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not reorder itinerary")
		return
	}
	defer tx.Rollback(ctx)
	q := store.New(tx)

	items, err := q.GetItineraryItemsByTrip(ctx, tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	if len(req.ItemIDs) != len(items) {
		writeJSONError(w, http.StatusConflict, "item list is out of date; reload the trip")
		return
	}
	existing := make(map[uuid.UUID]bool, len(items))
	for _, it := range items {
		existing[it.ID] = true
	}
	ordered := make([]uuid.UUID, 0, len(req.ItemIDs))
	seen := make(map[uuid.UUID]bool, len(req.ItemIDs))
	for _, raw := range req.ItemIDs {
		id, err := uuid.Parse(raw)
		if err != nil || !existing[id] || seen[id] {
			writeJSONError(w, http.StatusConflict, "item list is out of date; reload the trip")
			return
		}
		seen[id] = true
		ordered = append(ordered, id)
	}
	for pos, id := range ordered {
		if err := q.SetItineraryItemPosition(ctx, store.SetItineraryItemPositionParams{
			ID: id, TripID: tripID, Position: int32(pos),
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not reorder itinerary")
			return
		}
	}
	if err := q.TouchTrip(ctx, tripID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not reorder itinerary")
		return
	}
	if err := tx.Commit(ctx); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not reorder itinerary")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
