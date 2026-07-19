package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// checklist_handler.go — the per-trip packing/prep checklist. Its own table
// (trip_checklist_items), NOT booking_todos: unlike booking-todos, every row
// here is fully user-editable, including AI-seeded (auto=true) rows. Handlers
// mirror booking_todo_handler.go conventions: editableTrip gate (owner or
// active editor-collaborator), the same validation/404 shape, TouchTrip on
// mutation.

// allowedChecklistCategories bounds the free-text category to a known set so a
// stray value can't fragment the client's grouping. "general" is the default.
var allowedChecklistCategories = map[string]bool{
	"clothing":    true,
	"documents":   true,
	"electronics": true,
	"health":      true,
	"general":     true,
}

type ChecklistItemResponse struct {
	ID       string `json:"id"`
	Category string `json:"category"`
	Title    string `json:"title"`
	Checked  bool   `json:"checked"`
	Position int    `json:"position"`
	Auto     bool   `json:"auto"`
}

func toChecklistItemResponse(c store.TripChecklistItem) ChecklistItemResponse {
	return ChecklistItemResponse{
		ID:       c.ID.String(),
		Category: c.Category,
		Title:    c.Title,
		Checked:  c.Checked,
		Position: int(c.Position),
		Auto:     c.Auto,
	}
}

// normalizeChecklistCategory trims and lower-cases the category, defaulting to
// "general" when empty and rejecting unknown values.
func normalizeChecklistCategory(raw string) (string, bool) {
	c := strings.ToLower(strings.TrimSpace(raw))
	if c == "" {
		return "general", true
	}
	if !allowedChecklistCategories[c] {
		return "", false
	}
	return c, true
}

func listChecklistHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	writeChecklist(w, r, trip.ID)
}

type AddChecklistItemRequest struct {
	Category string `json:"category"`
	Title    string `json:"title"`
}

func addChecklistItemHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	var req AddChecklistItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	title := strings.TrimSpace(req.Title)
	if title == "" {
		writeJSONError(w, http.StatusBadRequest, "title is required")
		return
	}
	if _, err := boundedString("title", title, maxNameLen); err != nil {
		writeJSONError(w, http.StatusBadRequest, err.Error())
		return
	}
	category, valid := normalizeChecklistCategory(req.Category)
	if !valid {
		writeJSONError(w, http.StatusBadRequest, "category must be one of: clothing, documents, electronics, health, general")
		return
	}
	if n, err := store.New(dbPool).CountChecklistItemsByTrip(r.Context(), trip.ID); err == nil &&
		int(n) >= maxChecklistItemsPerTrip() {
		writeJSONError(w, http.StatusUnprocessableEntity,
			fmt.Sprintf("checklist is full (max %d items) — remove one first", maxChecklistItemsPerTrip()))
		return
	}

	item, err := store.New(dbPool).CreateChecklistItem(r.Context(), store.CreateChecklistItemParams{
		TripID:   trip.ID,
		Category: category,
		Title:    title,
		Position: 9999,
		Auto:     false,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save checklist item")
		return
	}
	_ = store.New(dbPool).TouchTrip(r.Context(), touchedBy(trip.ID, r))
	writeJSON(w, http.StatusCreated, toChecklistItemResponse(item))
}

// PatchChecklistItemRequest is a partial update: toggle checked, rename, move
// category, reposition. Unlike booking-todos there is no auto-gate — a row's
// auto flag never restricts edits.
type PatchChecklistItemRequest struct {
	Category *string `json:"category"`
	Title    *string `json:"title"`
	Checked  *bool   `json:"checked"`
	Position *int    `json:"position"`
}

func patchChecklistItemHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	itemID, err := uuid.Parse(mux.Vars(r)["itemId"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "checklist item not found")
		return
	}
	var req PatchChecklistItemRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if req.Category == nil && req.Title == nil && req.Checked == nil && req.Position == nil {
		writeJSONError(w, http.StatusBadRequest, "pass at least one field to change (category, title, checked, or position)")
		return
	}

	params := store.UpdateChecklistItemParams{ID: itemID, TripID: trip.ID}
	if req.Category != nil {
		category, valid := normalizeChecklistCategory(*req.Category)
		if !valid {
			writeJSONError(w, http.StatusBadRequest, "category must be one of: clothing, documents, electronics, health, general")
			return
		}
		params.Category = &category
	}
	if req.Title != nil {
		t := strings.TrimSpace(*req.Title)
		if t == "" {
			writeJSONError(w, http.StatusBadRequest, "title cannot be empty")
			return
		}
		if _, err := boundedString("title", t, maxNameLen); err != nil {
			writeJSONError(w, http.StatusBadRequest, err.Error())
			return
		}
		params.Title = &t
	}
	params.Checked = req.Checked
	if req.Position != nil {
		p := int32(*req.Position)
		params.Position = &p
	}

	item, err := store.New(dbPool).UpdateChecklistItem(r.Context(), params)
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "checklist item not found")
		return
	}
	_ = store.New(dbPool).TouchTrip(r.Context(), touchedBy(trip.ID, r))
	writeJSON(w, http.StatusOK, toChecklistItemResponse(item))
}

func deleteChecklistItemHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	itemID, err := uuid.Parse(mux.Vars(r)["itemId"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "checklist item not found")
		return
	}
	rows, err := store.New(dbPool).DeleteChecklistItem(r.Context(),
		store.DeleteChecklistItemParams{ID: itemID, TripID: trip.ID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete checklist item")
		return
	}
	if rows == 0 {
		writeJSONError(w, http.StatusNotFound, "checklist item not found")
		return
	}
	_ = store.New(dbPool).TouchTrip(r.Context(), touchedBy(trip.ID, r))
	w.WriteHeader(http.StatusNoContent)
}

func writeChecklist(w http.ResponseWriter, r *http.Request, tripID uuid.UUID) {
	items, err := store.New(dbPool).ListChecklistItemsByTrip(r.Context(), tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load checklist")
		return
	}
	resp := make([]ChecklistItemResponse, 0, len(items))
	for _, it := range items {
		resp = append(resp, toChecklistItemResponse(it))
	}
	writeJSON(w, http.StatusOK, resp)
}
