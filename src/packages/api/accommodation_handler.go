package main

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

type AccommodationResponse struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Provider  *string  `json:"provider,omitempty"`
	URL       *string  `json:"url,omitempty"`
	Address   *string  `json:"address,omitempty"`
	Latitude  *float64 `json:"latitude,omitempty"`
	Longitude *float64 `json:"longitude,omitempty"`
	CheckIn   *string  `json:"check_in,omitempty"`
	CheckOut  *string  `json:"check_out,omitempty"`
	PriceNote *string  `json:"price_note,omitempty"`
}

type AddAccommodationRequest struct {
	Name      string   `json:"name"`
	Provider  *string  `json:"provider"`
	URL       *string  `json:"url"`
	Address   *string  `json:"address"`
	Latitude  *float64 `json:"latitude"`
	Longitude *float64 `json:"longitude"`
	CheckIn   *string  `json:"check_in"`
	CheckOut  *string  `json:"check_out"`
	PriceNote *string  `json:"price_note"`
}

func toAccommodationResponse(a store.Accommodation) AccommodationResponse {
	return AccommodationResponse{
		ID:        a.ID.String(),
		Name:      a.Name,
		Provider:  a.Provider,
		URL:       a.Url,
		Address:   a.Address,
		Latitude:  a.Latitude,
		Longitude: a.Longitude,
		CheckIn:   dateToPtr(a.CheckIn),
		CheckOut:  dateToPtr(a.CheckOut),
		PriceNote: a.PriceNote,
	}
}

// accommodationLinksHandler builds Airbnb + Booking browse links. No auth needed.
func accommodationLinksHandler(w http.ResponseWriter, r *http.Request) {
	destination := strings.TrimSpace(r.URL.Query().Get("destination"))
	if destination == "" {
		writeJSONError(w, http.StatusBadRequest, "destination is required")
		return
	}
	guests, _ := strconv.Atoi(r.URL.Query().Get("guests"))
	links := providerLinks(AccommodationQuery{
		Destination: destination,
		CheckIn:     r.URL.Query().Get("check_in"),
		CheckOut:    r.URL.Query().Get("check_out"),
		Guests:      guests,
	})
	writeJSON(w, http.StatusOK, links)
}

// Trip mutations authorize via editableTrip (collaborator_handler.go): the
// owner or an active editor-collaborator on the trip's lineage. The former
// owner-only helper (ownedTrip) was retired when collaborative editing
// arrived; owner-only operations use GetTripByIDAndOwner directly.

func addAccommodationHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	tripID := trip.ID
	var req AddAccommodationRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if strings.TrimSpace(req.Name) == "" {
		writeJSONError(w, http.StatusBadRequest, "name is required")
		return
	}
	checkIn, err := parseDateParam(req.CheckIn)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "check_in must be YYYY-MM-DD")
		return
	}
	checkOut, err := parseDateParam(req.CheckOut)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "check_out must be YYYY-MM-DD")
		return
	}

	acc, err := store.New(dbPool).CreateAccommodation(r.Context(), store.CreateAccommodationParams{
		TripID:    tripID,
		Name:      strings.TrimSpace(req.Name),
		Provider:  req.Provider,
		Url:       req.URL,
		Address:   req.Address,
		Latitude:  req.Latitude,
		Longitude: req.Longitude,
		CheckIn:   checkIn,
		CheckOut:  checkOut,
		PriceNote: req.PriceNote,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save accommodation")
		return
	}
	writeJSON(w, http.StatusCreated, toAccommodationResponse(acc))
}

func deleteAccommodationHandler(w http.ResponseWriter, r *http.Request) {
	trip, ok := editableTrip(w, r)
	if !ok {
		return
	}
	tripID := trip.ID
	accID, err := uuid.Parse(mux.Vars(r)["accId"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "accommodation not found")
		return
	}
	rows, err := store.New(dbPool).DeleteAccommodation(r.Context(),
		store.DeleteAccommodationParams{ID: accID, TripID: tripID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete accommodation")
		return
	}
	if rows == 0 {
		writeJSONError(w, http.StatusNotFound, "accommodation not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
