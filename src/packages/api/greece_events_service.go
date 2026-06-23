package main

import (
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// GreekEventLink is a deep link to a Greek event/ticketing source. Greece has no
// public events API (Ticketmaster is effectively empty there), so for Greek
// cities we surface curated source links instead of structured Event cards —
// the same deep-link pattern as transport_service.go.
type GreekEventLink struct {
	Provider string `json:"provider"`
	URL      string `json:"url"`
	Label    string `json:"label"`
}

// greekCities is the set used to decide whether a city is in Greece. A robust
// country lookup (via Google Places details) is a follow-up; this hardcoded set
// covers the mainland hubs and the islands travelers actually plan around.
var greekCities = map[string]bool{
	"greece": true, "gr": true,
	"athens": true, "piraeus": true, "thessaloniki": true,
	"santorini": true, "thira": true, "fira": true, "oia": true,
	"mykonos": true, "naxos": true, "paros": true, "ios": true,
	"milos": true, "syros": true, "tinos": true, "folegandros": true,
	"crete": true, "heraklion": true, "chania": true, "rethymno": true,
	"rhodes": true, "kos": true, "corfu": true, "kefalonia": true,
	"zakynthos": true, "lefkada": true, "skiathos": true, "skopelos": true,
	"samos": true, "chios": true, "lesbos": true, "mytilene": true,
	"karpathos": true, "symi": true, "hydra": true, "spetses": true,
	"aegina": true, "nafplio": true, "delphi": true, "meteora": true,
	"kalamata": true, "patras": true,
}

// isGreekLocation reports whether a city/place name is in Greece, using the
// hardcoded greekCities set (case-insensitive, also matches a trailing
// ", Greece"). Used to switch the events flow to Greek source links.
func isGreekLocation(name string) bool {
	n := strings.ToLower(strings.TrimSpace(name))
	if n == "" {
		return false
	}
	if strings.Contains(n, "greece") {
		return true
	}
	// Match the first token (e.g. "Santorini, Greece" -> "santorini") and the
	// whole string.
	if greekCities[n] {
		return true
	}
	if i := strings.IndexAny(n, ","); i > 0 {
		if greekCities[strings.TrimSpace(n[:i])] {
			return true
		}
	}
	return false
}

// greekEventLinks returns curated event-discovery links for a Greek city over a
// date window (YYYY-MM-DD). more.com/Viva.gr is Greece's dominant ticketing
// platform; visitgreece.gr is the official tourism events calendar; the
// Athens-Epidaurus Festival is added only when the window overlaps its season
// (roughly May–October).
func greekEventLinks(city, startDate, endDate string) []GreekEventLink {
	c := strings.TrimSpace(city)
	links := []GreekEventLink{
		{
			Provider: "more.com",
			Label:    "Concerts, theatre & festivals on more.com",
			URL:      "https://www.more.com/gr-en/tickets/search/?q=" + url.QueryEscape(c),
		},
		{
			Provider: "visitgreece.gr",
			Label:    "Official events calendar",
			URL:      "https://www.visitgreece.gr/events/",
		},
	}
	if windowOverlapsFestivalSeason(startDate, endDate) {
		links = append(links, GreekEventLink{
			Provider: "Athens-Epidaurus Festival",
			Label:    "Athens & Epidaurus Festival (summer)",
			URL:      "https://aefestival.gr/schedule/?lang=en",
		})
	}
	return links
}

// greeceEventsLinksHandler returns curated Greek event-discovery links for a
// city + date window. Used by the trip-detail events section as the fallback
// when the structured (Ticketmaster) lookup is empty for a Greek city. Returns
// an empty list (not an error) for non-Greek cities so callers stay simple.
func greeceEventsLinksHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	q := r.URL.Query()
	city := strings.TrimSpace(q.Get("city"))
	if city == "" {
		http.Error(w, "Missing required query parameter 'city'", http.StatusBadRequest)
		return
	}

	var links []GreekEventLink
	if isGreekLocation(city) {
		links = greekEventLinks(city, q.Get("start_date"), q.Get("end_date"))
	} else {
		links = []GreekEventLink{}
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"links":  links,
		"status": "success",
	})
}

// windowOverlapsFestivalSeason reports whether [startDate,endDate] overlaps the
// Athens-Epidaurus Festival season (May–October), comparing on month so it
// holds across years. Defaults to true when dates are missing/unparseable so we
// don't hide the link on incomplete input.
func windowOverlapsFestivalSeason(startDate, endDate string) bool {
	s, errS := time.Parse("2006-01-02", strings.TrimSpace(startDate))
	e, errE := time.Parse("2006-01-02", strings.TrimSpace(endDate))
	if errS != nil || errE != nil {
		return true
	}
	for d := s; !d.After(e); d = d.AddDate(0, 0, 1) {
		if m := d.Month(); m >= time.May && m <= time.October {
			return true
		}
		// Bail out early once we're past October of the start year and the
		// window can't loop back into season.
		if d.Sub(s) > 366*24*time.Hour {
			break
		}
	}
	return false
}
