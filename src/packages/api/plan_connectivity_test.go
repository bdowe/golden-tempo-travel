package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"context"
)

// --- helpers ---------------------------------------------------------------

// connStub is a path-aware fake Duffel: /places/suggestions answers airport
// lookups, /air/offer_requests answers per-route canned offers. It records
// every offer request's route and query string.
type connStub struct {
	mu         sync.Mutex
	offers     map[string]string // "ORIG-DEST" -> offers JSON body
	places     map[string]string // query keyword -> places JSON body
	delays     map[string]time.Duration
	requests   []string // "ORIG-DEST" per offer request
	rawQueries []string
}

func (cs *connStub) handler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/places/suggestions" {
			body := cs.places[r.URL.Query().Get("query")]
			if body == "" {
				body = `{"data":[]}`
			}
			w.Write([]byte(body))
			return
		}
		raw, _ := io.ReadAll(r.Body)
		var req struct {
			Data struct {
				Slices []struct {
					Origin      string `json:"origin"`
					Destination string `json:"destination"`
				} `json:"slices"`
			} `json:"data"`
		}
		json.Unmarshal(raw, &req)
		route := "?-?"
		if len(req.Data.Slices) > 0 {
			route = req.Data.Slices[0].Origin + "-" + req.Data.Slices[0].Destination
		}
		cs.mu.Lock()
		cs.requests = append(cs.requests, route)
		cs.rawQueries = append(cs.rawQueries, r.URL.RawQuery)
		delay := cs.delays[route]
		cs.mu.Unlock()
		if delay > 0 {
			time.Sleep(delay)
		}
		body := cs.offers[route]
		if body == "" {
			body = `{"data":{"offers":[]}}`
		}
		w.Write([]byte(body))
	}
}

func (cs *connStub) requestCount() int {
	cs.mu.Lock()
	defer cs.mu.Unlock()
	return len(cs.requests)
}

// swapConnStub serves the stub and swaps the process-wide duffelService (set
// at package init, so DUFFEL_BASE_URL alone can't reach it in-process). Also
// swaps connectivityCache so tests never see each other's legs.
func swapConnStub(t *testing.T, cs *connStub) {
	t.Helper()
	srv := httptest.NewServer(cs.handler())
	t.Cleanup(srv.Close)
	stub := &DuffelService{
		Token: "test-token", BaseURL: srv.URL, Version: "v2",
		Client:      &http.Client{Timeout: 5 * time.Second},
		placesCache: newTTLCache[[]Airport](time.Hour, 100),
	}
	oldDuffel := duffelService
	duffelService = stub
	oldCache := connectivityCache
	connectivityCache = newTTLCache[legConnectivity](45*time.Minute, 2000)
	t.Cleanup(func() {
		duffelService = oldDuffel
		connectivityCache = oldCache
	})
}

// connOffer builds one offer's JSON with stops+1 segments.
func connOffer(id, amount, currency, duration string, stops int) string {
	segs := make([]string, 0, stops+1)
	for i := 0; i <= stops; i++ {
		segs = append(segs, fmt.Sprintf(`{
			"origin":{"iata_code":"A%d"},"destination":{"iata_code":"B%d"},
			"departing_at":"2026-09-15T08:00:00","arriving_at":"2026-09-15T12:00:00",
			"marketing_carrier":{"name":"TestAir","iata_code":"TA"},
			"marketing_carrier_flight_number":"10%d"}`, i, i, i))
	}
	return fmt.Sprintf(`{"id":%q,"total_amount":%q,"total_currency":%q,
		"owner":{"iata_code":"TA","name":"TestAir"},
		"slices":[{"duration":%q,"segments":[%s]}]}`,
		id, amount, currency, duration, strings.Join(segs, ","))
}

func offersBody(offers ...string) string {
	return `{"data":{"offers":[` + strings.Join(offers, ",") + `]}}`
}

func connSession() *planSession {
	return &planSession{ctx: context.Background(), w: httptest.NewRecorder()}
}

func connInput(t *testing.T, origin string, candidates []string, date, onward string) json.RawMessage {
	t.Helper()
	in := map[string]any{"origin": origin, "candidates": candidates, "depart_date": date}
	if onward != "" {
		in["onward_destination"] = onward
	}
	b, err := json.Marshal(in)
	if err != nil {
		t.Fatalf("marshal input: %v", err)
	}
	return b
}

// --- tests -----------------------------------------------------------------

// The reduction takes each minimum independently — the cheapest, fastest, and
// fewest-stops offers may be different flights.
func TestConnectivityFromOffers(t *testing.T) {
	offers := []FlightOffer{
		{Price: 512, Currency: "USD", DurationMin: 425, Stops: 1},
		{Price: 388, Currency: "EUR", DurationMin: 580, Stops: 2},
		{Price: 700, Currency: "USD", DurationMin: 210, Stops: 0},
	}
	conn := connectivityFromOffers("SJU", "BDA", offers)
	if conn.Cheapest != 388 || conn.Currency != "EUR" {
		t.Fatalf("cheapest = %v %v, want 388 EUR (currency follows the cheapest offer)", conn.Currency, conn.Cheapest)
	}
	if conn.FastestMin != 210 {
		t.Fatalf("fastest = %d, want 210", conn.FastestMin)
	}
	if conn.MinStops != 0 {
		t.Fatalf("min stops = %d, want 0", conn.MinStops)
	}
	if conn.OfferCount != 3 {
		t.Fatalf("offer count = %d, want 3", conn.OfferCount)
	}

	empty := connectivityFromOffers("SJU", "XXX", nil)
	if empty.OfferCount != 0 {
		t.Fatalf("empty offers must report OfferCount 0, got %d", empty.OfferCount)
	}
}

// Fan-out: candidates + onward produce one deduped offer request per leg, each
// carrying the reduced supplier timeout; the summary has one numbered line per
// candidate covering both legs; nothing is written to the SSE stream.
func TestRunCheckFlightConnectivityFanout(t *testing.T) {
	cs := &connStub{offers: map[string]string{
		"SJU-BDA": offersBody(connOffer("o1", "1450.00", "USD", "PT12H05M", 2)),
		"BDA-BTV": offersBody(connOffer("o2", "388.00", "USD", "PT9H40M", 1)),
		"SJU-NAS": offersBody(connOffer("o3", "210.00", "USD", "PT3H30M", 0)),
		"NAS-BTV": offersBody(connOffer("o4", "305.00", "USD", "PT7H10M", 1)),
		// SJU-GCM intentionally absent -> empty offers = "no flights found".
		"GCM-BTV": offersBody(connOffer("o5", "410.00", "USD", "PT8H00M", 1)),
	}}
	swapConnStub(t, cs)

	s := connSession()
	out, isErr := runCheckFlightConnectivityTool(s,
		connInput(t, "SJU", []string{"BDA", "NAS", "GCM"}, "2026-09-15", "BTV"))
	if isErr {
		t.Fatalf("tool errored: %s", out)
	}

	if got := cs.requestCount(); got != 6 {
		t.Fatalf("offer requests = %d (%v), want 6 deduped legs", got, cs.requests)
	}
	for i, q := range cs.rawQueries {
		if !strings.Contains(q, "supplier_timeout=10000") {
			t.Fatalf("request %d query %q missing supplier_timeout=10000", i, q)
		}
	}

	for _, want := range []string{
		"1. BDA (BDA): SJU→BDA — from USD 1450, fastest 12h05m, min 2 stops (no nonstop); BDA→BTV — from USD 388, fastest 9h40m, min 1 stop (no nonstop)",
		"2. NAS (NAS): SJU→NAS — from USD 210, fastest 3h30m, nonstop available; NAS→BTV — from USD 305, fastest 7h10m, min 1 stop (no nonstop)",
		"3. GCM (GCM): SJU→GCM — no flights found for this date (poorly connected or no service); GCM→BTV — from USD 410",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("summary missing %q:\n%s", want, out)
		}
	}

	// The comparison must not stream flight cards (or anything else).
	if body := s.w.(*httptest.ResponseRecorder).Body.String(); body != "" {
		t.Fatalf("tool wrote to the SSE stream: %q", body)
	}
}

// A leg that outlives the tool deadline is reported unknown; the rest of the
// comparison still succeeds.
func TestConnectivityPartialTimeout(t *testing.T) {
	cs := &connStub{
		offers: map[string]string{
			"SJU-NAS": offersBody(connOffer("o1", "210.00", "USD", "PT3H30M", 0)),
			"SJU-GCM": offersBody(connOffer("o2", "300.00", "USD", "PT4H00M", 1)),
		},
		delays: map[string]time.Duration{"SJU-GCM": 2 * time.Second},
	}
	swapConnStub(t, cs)
	oldTimeout := connectivityToolTimeout
	connectivityToolTimeout = 300 * time.Millisecond
	t.Cleanup(func() { connectivityToolTimeout = oldTimeout })

	out, isErr := runCheckFlightConnectivityTool(connSession(),
		connInput(t, "SJU", []string{"NAS", "GCM"}, "2026-09-15", ""))
	if isErr {
		t.Fatalf("partial results must not be an error: %s", out)
	}
	if !strings.Contains(out, "SJU→NAS — from USD 210") {
		t.Fatalf("fast leg missing real numbers:\n%s", out)
	}
	if !strings.Contains(out, "SJU→GCM — timed out, connectivity unknown") {
		t.Fatalf("slow leg not reported as timed out:\n%s", out)
	}
}

// Candidate and per-session caps bound Duffel spend.
func TestConnectivityCaps(t *testing.T) {
	cs := &connStub{offers: map[string]string{}}
	swapConnStub(t, cs)

	s := connSession()
	seven := []string{"AAA", "BBB", "CCC", "DDD", "EEE", "FFF", "GGG"}
	out, _ := runCheckFlightConnectivityTool(s, connInput(t, "SJU", seven, "2026-09-15", ""))
	if got := cs.requestCount(); got != maxConnectivityCandidates {
		t.Fatalf("offer requests = %d, want %d (truncated)", got, maxConnectivityCandidates)
	}
	if !strings.Contains(out, "Only the first 5 candidates were checked") {
		t.Fatalf("truncation note missing:\n%s", out)
	}
	if strings.Contains(out, "FFF") || strings.Contains(out, "GGG") {
		t.Fatalf("truncated candidates leaked into the summary:\n%s", out)
	}

	// Calls 2 and 3 are allowed (distinct dates dodge the leg cache);
	// call 4 must return the friendly cap message without touching Duffel.
	runCheckFlightConnectivityTool(s, connInput(t, "SJU", []string{"AAA", "BBB"}, "2026-09-16", ""))
	runCheckFlightConnectivityTool(s, connInput(t, "SJU", []string{"AAA", "BBB"}, "2026-09-17", ""))
	before := cs.requestCount()
	out, isErr := runCheckFlightConnectivityTool(s, connInput(t, "SJU", []string{"AAA", "BBB"}, "2026-09-18", ""))
	if isErr {
		t.Fatalf("cap message must not be an error result (the model would retry): %s", out)
	}
	if !strings.Contains(out, "limit reached") {
		t.Fatalf("capped call missing limit message: %s", out)
	}
	if got := cs.requestCount(); got != before {
		t.Fatalf("capped call still hit Duffel: %d -> %d requests", before, got)
	}
}

// Identical legs are answered from the 45-minute cache — a second comparison
// issues zero new Duffel requests, even from another session.
func TestConnectivityCacheHit(t *testing.T) {
	cs := &connStub{offers: map[string]string{
		"SJU-NAS": offersBody(connOffer("o1", "210.00", "USD", "PT3H30M", 0)),
		"SJU-BDA": offersBody(connOffer("o2", "512.00", "USD", "PT7H05M", 1)),
	}}
	swapConnStub(t, cs)

	first, _ := runCheckFlightConnectivityTool(connSession(),
		connInput(t, "SJU", []string{"NAS", "BDA"}, "2026-09-15", ""))
	if got := cs.requestCount(); got != 2 {
		t.Fatalf("first call requests = %d, want 2", got)
	}
	second, _ := runCheckFlightConnectivityTool(connSession(),
		connInput(t, "SJU", []string{"NAS", "BDA"}, "2026-09-15", ""))
	if got := cs.requestCount(); got != 2 {
		t.Fatalf("second call issued %d new requests, want 0 (cache)", cs.requestCount()-2)
	}
	if !strings.Contains(second, "SJU→NAS — from USD 210") || first == "" {
		t.Fatalf("cached call lost the real numbers:\n%s", second)
	}
}

// A place Duffel can't resolve becomes a named row; the comparison proceeds
// for everything else.
func TestConnectivityUnresolvedCandidate(t *testing.T) {
	cs := &connStub{
		offers: map[string]string{
			"SJU-NAS": offersBody(connOffer("o1", "210.00", "USD", "PT3H30M", 0)),
		},
		places: map[string]string{}, // "Isla Perdida" -> {"data":[]}
	}
	swapConnStub(t, cs)

	out, isErr := runCheckFlightConnectivityTool(connSession(),
		connInput(t, "SJU", []string{"Isla Perdida", "NAS"}, "2026-09-15", ""))
	if isErr {
		t.Fatalf("one unresolvable candidate must not fail the tool: %s", out)
	}
	if !strings.Contains(out, `Could not resolve "Isla Perdida" to an airport`) {
		t.Fatalf("missing unresolvable row:\n%s", out)
	}
	if !strings.Contains(out, "SJU→NAS — from USD 210") {
		t.Fatalf("resolvable candidate missing:\n%s", out)
	}
	if got := cs.requestCount(); got != 1 {
		t.Fatalf("offer requests = %d, want 1 (no leg for the unresolved place)", got)
	}
}

// An unresolvable origin is a hard error — nothing can be compared.
func TestConnectivityUnresolvedOrigin(t *testing.T) {
	cs := &connStub{}
	swapConnStub(t, cs)

	out, isErr := runCheckFlightConnectivityTool(connSession(),
		connInput(t, "Nowhere Specific", []string{"NAS", "BDA"}, "2026-09-15", ""))
	if !isErr {
		t.Fatalf("unresolvable origin must be an error, got: %s", out)
	}
	if got := cs.requestCount(); got != 0 {
		t.Fatalf("offer requests = %d, want 0", got)
	}
}
