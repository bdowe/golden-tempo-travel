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

// greekPortCodes maps the island/port names we recognize (lowercased) to their
// Ferryhopper port codes, sourced authoritatively from the Ferryhopper MCP
// get_ports tool (not guessed — ferry-only ports like Rafina/Hydra/Aegina have
// no IATA code). Covers the same set as the Flutter _greekIslands gate, so every
// ferry leg we offer resolves to a real port code. Athens/Piraeus → PIR (the
// main ferry hub); multi-port islands use their "all ports" code.
var greekPortCodes = map[string]string{
	"athens": "PIR", "piraeus": "PIR",
	"santorini": "JTR", "thira": "JTR", "fira": "JTR", "oia": "JTR",
	"mykonos": "JMK", "naxos": "JNX", "paros": "PAS", "ios": "IOS",
	"milos": "MLO", "syros": "JSY", "tinos": "TIN", "folegandros": "FOL",
	"crete": "HER", "heraklion": "HER", "chania": "CHA", "rethymno": "RNO",
	"rhodes": "RHO", "kos": "KGS", "corfu": "CFU", "kefalonia": "KE00",
	"zakynthos": "ZTH", "lefkada": "LEF00", "skiathos": "JSI", "skopelos": "SKO",
	"samos": "SMS", "chios": "CHI", "lesbos": "LES", "mytilene": "LES",
	"karpathos": "AOK", "symi": "SYM", "hydra": "HYD", "spetses": "SPE",
	"aegina": "AEG",
}

// ferryPortCode resolves a port/island name to its Ferryhopper code, handling a
// trailing ", Greece" and surrounding whitespace. Empty string when unknown.
func ferryPortCode(name string) string {
	n := strings.ToLower(strings.TrimSpace(name))
	if c, ok := greekPortCodes[n]; ok {
		return c
	}
	if i := strings.IndexByte(n, ','); i > 0 {
		if c, ok := greekPortCodes[strings.TrimSpace(n[:i])]; ok {
			return c
		}
	}
	return ""
}

// SearchFerries returns ferry options for a route. v1 returns a single
// link-only option pointing at the Ferryhopper booking-results search for the
// exact route and date. Returns nil when origin or destination is missing.
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
		BookingURL: s.ferryhopperURL(from, to, strings.TrimSpace(q.Date)),
	}}
}

// ferryhopperURL builds a Ferryhopper booking-results deep link for a specific
// route and date — the same format Ferryhopper's own "Find tickets" buttons use:
// /en/booking/results?itinerary=CODE1,CODE2&dates=YYYYMMDD. The query is built
// by hand so the comma in itinerary stays literal (matching Ferryhopper), not
// percent-encoded. When either port code is unknown, falls back to the ferries
// schedules landing page rather than a broken route (never the homepage).
func (s *FerryService) ferryhopperURL(from, to, date string) string {
	fromCode := ferryPortCode(from)
	toCode := ferryPortCode(to)
	if fromCode == "" || toCode == "" {
		return "https://www.ferryhopper.com/en/ferries"
	}
	u := "https://www.ferryhopper.com/en/booking/results?itinerary=" + fromCode + "," + toCode
	if d := strings.ReplaceAll(date, "-", ""); len(d) == 8 {
		u += "&dates=" + d
	}
	if s.AffiliateID != "" {
		u += "&aff=" + url.QueryEscape(s.AffiliateID)
	}
	return u
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
