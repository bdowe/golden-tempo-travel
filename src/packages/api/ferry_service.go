package main

import (
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// FerryQuery describes a ferry search between two ports/islands.
type FerryQuery struct {
	Origin      string // island/port name, e.g. "Santorini"
	Destination string // island/port name, e.g. "Naxos"
	Date        string // YYYY-MM-DD (optional)
	Passengers  int    // optional
}

// FerryOption is the normalized, forward-compatible ferry result. The v1
// (affiliate deep-link) path fills only From/To/Date/BookingURL; the structured
// fields stay empty until a real ferry API (Ferryhopper FerryhAPI) is wired in
// behind the same SearchFerries signature, populating the same shape without
// touching callers, the agent, or the Flutter app.
type FerryOption struct {
	Operator    string  `json:"operator,omitempty"`
	From        string  `json:"from"`
	To          string  `json:"to"`
	Date        string  `json:"date,omitempty"` // YYYY-MM-DD
	DepartTime  string  `json:"depart_time,omitempty"`
	ArriveTime  string  `json:"arrive_time,omitempty"`
	DurationMin int     `json:"duration_minutes,omitempty"`
	Price       float64 `json:"price,omitempty"`
	Currency    string  `json:"currency,omitempty"`
	BookingURL  string  `json:"booking_url"` // Ferryhopper (affiliate) deep link
}

// FerryService builds ferry booking links. Today it produces Ferryhopper
// deep links; a future listing-returning provider (FerryhAPI) can replace
// SearchFerries' body without changing the FerryOption shape or callers.
type FerryService struct {
	AffiliateID string
}

// NewFerryService reads the optional Ferryhopper affiliate id. Absence is fine —
// links still work, they're just unattributed.
func NewFerryService() *FerryService {
	return &FerryService{
		AffiliateID: os.Getenv("FERRYHOPPER_AFFILIATE_ID"),
	}
}

// ferryService is a process-wide singleton (it holds only static config).
var ferryService = NewFerryService()

// SearchFerries returns ferry options for a route. v1 returns a single
// link-only option pointing at the Ferryhopper route page (which lists real
// schedules and prices and has a date picker). Returns nil when origin or
// destination is missing.
func (s *FerryService) SearchFerries(q FerryQuery) []FerryOption {
	from := strings.TrimSpace(q.Origin)
	to := strings.TrimSpace(q.Destination)
	if from == "" || to == "" {
		return nil
	}
	return []FerryOption{{
		From:       from,
		To:         to,
		Date:       strings.TrimSpace(q.Date),
		BookingURL: s.ferryhopperURL(from, to),
	}}
}

// ferryhopperURL builds a Ferryhopper route-page deep link from island/port
// names (verified scheme: /en/ferry-routes/direct/{from}-to-{to}). The route
// page resolves by name and shows live schedules/prices. The affiliate id, when
// configured, is appended per the Ferryhopper affiliate agreement.
//
// Upgrade path: Ferryhopper's booking-results page is date-aware
// (/en/booking/results?itinerary=PIR,JTR&dates=YYYYMMDD) but needs port codes;
// switch to it once a port-code map or FerryhAPI is available.
func (s *FerryService) ferryhopperURL(from, to string) string {
	u := "https://www.ferryhopper.com/en/ferry-routes/direct/" +
		ferrySlug(from) + "-to-" + ferrySlug(to)
	if s.AffiliateID != "" {
		u += "?" + url.Values{"aff": {s.AffiliateID}}.Encode()
	}
	return u
}

// ferrySlug lowercases and hyphenates a port/island name for Ferryhopper's
// route-page path segments.
func ferrySlug(s string) string {
	return url.PathEscape(strings.ToLower(strings.ReplaceAll(strings.TrimSpace(s), " ", "-")))
}

// ferriesSearchHandler handles ferry route search requests. Mirrors
// eventsSearchHandler's response shape.
func ferriesSearchHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	q := r.URL.Query()
	origin := strings.TrimSpace(q.Get("origin"))
	destination := strings.TrimSpace(q.Get("destination"))
	date := strings.TrimSpace(q.Get("date"))
	if origin == "" || destination == "" {
		http.Error(w, "Missing required query parameters 'origin' and 'destination'", http.StatusBadRequest)
		return
	}
	passengers, _ := strconv.Atoi(q.Get("passengers"))

	options := ferryService.SearchFerries(FerryQuery{
		Origin:      origin,
		Destination: destination,
		Date:        date,
		Passengers:  passengers,
	})

	json.NewEncoder(w).Encode(map[string]interface{}{
		"options": options,
		"status":  "success",
	})
}
