package main

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

var allowedBookingKinds = map[string]bool{"stay": true, "transport": true, "other": true}

type BookingTodoResponse struct {
	ID         string  `json:"id"`
	Kind       string  `json:"kind"`
	TodoKey    string  `json:"todo_key"`
	Title      string  `json:"title"`
	Subtitle   *string `json:"subtitle,omitempty"`
	Provider   *string `json:"provider,omitempty"`
	SearchURL  *string `json:"search_url,omitempty"`
	DepartDate *string `json:"depart_date,omitempty"`
	ReturnDate *string `json:"return_date,omitempty"`
	Booked     bool    `json:"booked"`
	Auto       bool    `json:"auto"`
	Position   int     `json:"position"`
}

func toBookingTodoResponse(t store.BookingTodo) BookingTodoResponse {
	return BookingTodoResponse{
		ID:         t.ID.String(),
		Kind:       t.Kind,
		TodoKey:    t.TodoKey,
		Title:      t.Title,
		Subtitle:   t.Subtitle,
		Provider:   t.Provider,
		SearchURL:  t.SearchUrl,
		DepartDate: dateToPtr(t.DepartDate),
		ReturnDate: dateToPtr(t.ReturnDate),
		Booked:     t.Booked,
		Auto:       t.Auto,
		Position:   int(t.Position),
	}
}

// DerivedBookingTodo is one auto-generated checklist entry sent by the client.
// The client supplies the itinerary-derived metadata plus the inputs needed to
// build the search link; the server resolves search_url via the existing
// provider link builders so URL construction stays in one place.
type DerivedBookingTodo struct {
	Kind        string  `json:"kind"`
	TodoKey     string  `json:"todo_key"`
	Title       string  `json:"title"`
	Subtitle    *string `json:"subtitle"`
	Provider    *string `json:"provider"`
	Position    int     `json:"position"`
	DepartDate  *string `json:"depart_date"` // stay check-in / transport depart
	ReturnDate  *string `json:"return_date"` // stay check-out
	Destination string  `json:"destination"`
	Origin      *string `json:"origin"`
	Guests      int     `json:"guests"`
	Passengers  int     `json:"passengers"`
}

// bookingSearchURL resolves the search link for a derived/custom TODO using the
// shared provider builders. It returns the URL and the provider name actually
// used (which may differ from a requested provider if that one isn't available).
func bookingSearchURL(kind, destination string, origin *string, departDate, returnDate *string, guests, passengers int, preferred *string) (string, string) {
	pref := ""
	if preferred != nil {
		pref = *preferred
	}
	switch kind {
	case "stay":
		if strings.TrimSpace(destination) == "" {
			return "", ""
		}
		links := providerLinks(AccommodationQuery{
			Destination: destination,
			CheckIn:     strPtrVal(departDate),
			CheckOut:    strPtrVal(returnDate),
			Guests:      guests,
		})
		return pickProviderLink(links, pref)
	case "transport":
		o := strPtrVal(origin)
		if strings.TrimSpace(o) == "" || strings.TrimSpace(destination) == "" {
			return "", ""
		}
		links := transportLinks(TransportQuery{
			Mode:        "flight",
			Origin:      o,
			Destination: destination,
			DepartDate:  strPtrVal(departDate),
			Passengers:  passengers,
		})
		out := make([]ProviderLink, 0, len(links))
		for _, l := range links {
			out = append(out, ProviderLink{Provider: l.Provider, URL: l.URL})
		}
		return pickProviderLink(out, pref)
	default:
		return "", ""
	}
}

// pickProviderLink returns the URL+name for the preferred provider, falling back
// to the first available link.
func pickProviderLink(links []ProviderLink, preferred string) (string, string) {
	if len(links) == 0 {
		return "", ""
	}
	for _, l := range links {
		if l.Provider == preferred {
			return l.URL, l.Provider
		}
	}
	return links[0].URL, links[0].Provider
}

func strPtrVal(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func strPtrOrNil(s string) *string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	return &s
}

// syncBookingTodosHandler upserts the client's itinerary-derived auto-TODOs and
// prunes any auto rows whose legs no longer exist, preserving the booked flag
// across syncs. Returns the full ordered list.
func syncBookingTodosHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	var derived []DerivedBookingTodo
	if err := json.NewDecoder(r.Body).Decode(&derived); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	q := store.New(dbPool)
	keys := make([]string, 0, len(derived))
	for _, d := range derived {
		kind := strings.TrimSpace(d.Kind)
		if !allowedBookingKinds[kind] || strings.TrimSpace(d.TodoKey) == "" || strings.TrimSpace(d.Title) == "" {
			writeJSONError(w, http.StatusBadRequest, "each todo needs a valid kind, todo_key, and title")
			return
		}
		depart, err := parseDateParam(d.DepartDate)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "depart_date must be YYYY-MM-DD")
			return
		}
		ret, err := parseDateParam(d.ReturnDate)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "return_date must be YYYY-MM-DD")
			return
		}
		url, provider := bookingSearchURL(kind, d.Destination, d.Origin, d.DepartDate, d.ReturnDate, d.Guests, d.Passengers, d.Provider)
		providerPtr := strPtrOrNil(provider)
		if providerPtr == nil {
			providerPtr = d.Provider
		}
		if _, err := q.UpsertBookingTodo(r.Context(), store.UpsertBookingTodoParams{
			TripID:     tripID,
			Kind:       kind,
			TodoKey:    d.TodoKey,
			Title:      strings.TrimSpace(d.Title),
			Subtitle:   d.Subtitle,
			Provider:   providerPtr,
			SearchUrl:  strPtrOrNil(url),
			DepartDate: depart,
			ReturnDate: ret,
			Position:   int32(d.Position),
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not save booking todo")
			return
		}
		keys = append(keys, d.TodoKey)
	}

	if _, err := q.DeleteStaleAutoBookingTodos(r.Context(), store.DeleteStaleAutoBookingTodosParams{
		TripID: tripID,
		Keys:   keys,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not prune booking todos")
		return
	}

	writeBookingTodos(w, r, tripID)
}

type AddBookingTodoRequest struct {
	Kind        string  `json:"kind"`
	Title       string  `json:"title"`
	Provider    *string `json:"provider"`
	SearchURL   *string `json:"search_url"`
	Subtitle    *string `json:"subtitle"`
	Destination *string `json:"destination"`
	Origin      *string `json:"origin"`
	DepartDate  *string `json:"depart_date"`
	ReturnDate  *string `json:"return_date"`
	Guests      int     `json:"guests"`
	Passengers  int     `json:"passengers"`
}

// addBookingTodoHandler creates a user-defined (auto=false) checklist entry. A
// search_url may be supplied directly, or built from a destination via the
// provider link builders.
func addBookingTodoHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	var req AddBookingTodoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	kind := strings.TrimSpace(req.Kind)
	if !allowedBookingKinds[kind] {
		writeJSONError(w, http.StatusBadRequest, "kind must be one of: stay, transport, other")
		return
	}
	if strings.TrimSpace(req.Title) == "" {
		writeJSONError(w, http.StatusBadRequest, "title is required")
		return
	}
	depart, err := parseDateParam(req.DepartDate)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "depart_date must be YYYY-MM-DD")
		return
	}
	ret, err := parseDateParam(req.ReturnDate)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "return_date must be YYYY-MM-DD")
		return
	}

	url := strPtrVal(req.SearchURL)
	provider := strPtrVal(req.Provider)
	if strings.TrimSpace(url) == "" && req.Destination != nil {
		url, provider = bookingSearchURL(kind, strPtrVal(req.Destination), req.Origin, req.DepartDate, req.ReturnDate, req.Guests, req.Passengers, req.Provider)
	}

	todo, err := store.New(dbPool).CreateBookingTodo(r.Context(), store.CreateBookingTodoParams{
		TripID:     tripID,
		Kind:       kind,
		TodoKey:    "custom:" + uuid.NewString(),
		Title:      strings.TrimSpace(req.Title),
		Subtitle:   req.Subtitle,
		Provider:   strPtrOrNil(provider),
		SearchUrl:  strPtrOrNil(url),
		DepartDate: depart,
		ReturnDate: ret,
		Position:   9999,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not save booking todo")
		return
	}
	writeJSON(w, http.StatusCreated, toBookingTodoResponse(todo))
}

type PatchBookingTodoRequest struct {
	Booked *bool `json:"booked"`
}

func patchBookingTodoHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	todoID, err := uuid.Parse(mux.Vars(r)["todoId"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "booking todo not found")
		return
	}
	var req PatchBookingTodoRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if req.Booked == nil {
		writeJSONError(w, http.StatusBadRequest, "booked is required")
		return
	}
	todo, err := store.New(dbPool).SetBookingTodoBooked(r.Context(), store.SetBookingTodoBookedParams{
		ID:     todoID,
		TripID: tripID,
		Booked: *req.Booked,
	})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "booking todo not found")
		return
	}
	writeJSON(w, http.StatusOK, toBookingTodoResponse(todo))
}

func deleteBookingTodoHandler(w http.ResponseWriter, r *http.Request) {
	tripID, ok := ownedTrip(w, r)
	if !ok {
		return
	}
	todoID, err := uuid.Parse(mux.Vars(r)["todoId"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "booking todo not found")
		return
	}
	rows, err := store.New(dbPool).DeleteBookingTodo(r.Context(),
		store.DeleteBookingTodoParams{ID: todoID, TripID: tripID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete booking todo")
		return
	}
	if rows == 0 {
		writeJSONError(w, http.StatusNotFound, "booking todo not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeBookingTodos(w http.ResponseWriter, r *http.Request, tripID uuid.UUID) {
	todos, err := store.New(dbPool).ListBookingTodosByTrip(r.Context(), tripID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load booking todos")
		return
	}
	resp := make([]BookingTodoResponse, 0, len(todos))
	for _, t := range todos {
		resp = append(resp, toBookingTodoResponse(t))
	}
	writeJSON(w, http.StatusOK, resp)
}
