package main

import (
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
)

// countingTransport serves a canned JSON body and counts round trips, so tests
// can assert how many billable Google calls a code path would make.
type countingTransport struct {
	calls int
	body  string
}

func (c *countingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	c.calls++
	return &http.Response{
		StatusCode: http.StatusOK,
		Header:     http.Header{"Content-Type": []string{"application/json"}},
		Body:       io.NopCloser(strings.NewReader(c.body)),
	}, nil
}

const fakeTextSearchJSON = `{"status":"OK","results":[{"place_id":"p1","name":"Louvre Museum","formatted_address":"Paris","geometry":{"location":{"lat":48.86,"lng":2.34}},"types":["museum"]}]}`

const fakePlaceDetailsJSON = `{"status":"OK","result":{"place_id":"p1","name":"Louvre Museum","formatted_address":"Paris","geometry":{"location":{"lat":48.86,"lng":2.34}},"types":["museum"]}}`

// The whole point of the placesService singleton is that the TTL caches
// survive across calls: identical searches must hit Google exactly once.
func TestSearchPlacesServedFromCache(t *testing.T) {
	rt := &countingTransport{body: fakeTextSearchJSON}
	svc := NewGooglePlacesService()
	svc.APIKey = "test-key"
	svc.Client = &http.Client{Transport: rt}

	first, err := svc.SearchPlaces("Louvre Museum Paris")
	if err != nil {
		t.Fatalf("first search failed: %v", err)
	}
	// Same query modulo case/whitespace must hit the cache, not Google.
	second, err := svc.SearchPlaces("  louvre museum paris ")
	if err != nil {
		t.Fatalf("second search failed: %v", err)
	}

	if rt.calls != 1 {
		t.Fatalf("Google called %d times, want 1 (second lookup must come from cache)", rt.calls)
	}
	if len(first) != 1 || len(second) != 1 || second[0].PlaceID != "p1" {
		t.Fatalf("cached result mismatch: first=%v second=%v", first, second)
	}

	// The COGS counters must mirror what actually happened: one billable
	// upstream call (the miss), one cache hit (no upstream increment).
	if got := svc.searchCalls.snapshot(); got.Upstream != 1 || got.CacheHits != 1 {
		t.Fatalf("search counters = %+v, want upstream=1 cache_hits=1", got)
	}
	if got := svc.autocompleteCalls.snapshot(); got.Upstream != 0 || got.CacheHits != 0 {
		t.Fatalf("autocomplete counters moved on a search-only path: %+v", got)
	}
}

func TestGetPlaceDetailsServedFromCache(t *testing.T) {
	rt := &countingTransport{body: fakePlaceDetailsJSON}
	svc := NewGooglePlacesService()
	svc.APIKey = "test-key"
	svc.Client = &http.Client{Transport: rt}

	if _, err := svc.GetPlaceDetails("p1"); err != nil {
		t.Fatalf("first details call failed: %v", err)
	}
	got, err := svc.GetPlaceDetails("p1")
	if err != nil {
		t.Fatalf("second details call failed: %v", err)
	}
	if rt.calls != 1 {
		t.Fatalf("Google called %d times, want 1", rt.calls)
	}
	if got == nil || got.Name != "Louvre Museum" {
		t.Fatalf("cached details mismatch: %+v", got)
	}
	if c := svc.detailsCalls.snapshot(); c.Upstream != 1 || c.CacheHits != 1 {
		t.Fatalf("details counters = %+v, want upstream=1 cache_hits=1", c)
	}
}

const fakeAutocompleteJSON = `{"status":"OK","predictions":[{"place_id":"p1","description":"Louvre Museum, Paris","types":["museum"]}]}`

func TestAutocompleteCountersTrackMissAndHit(t *testing.T) {
	rt := &countingTransport{body: fakeAutocompleteJSON}
	svc := NewGooglePlacesService()
	svc.APIKey = "test-key"
	svc.Client = &http.Client{Transport: rt}

	if _, err := svc.GetPlaceAutocomplete("louvre"); err != nil {
		t.Fatalf("first autocomplete failed: %v", err)
	}
	if _, err := svc.GetPlaceAutocomplete(" LOUVRE "); err != nil {
		t.Fatalf("second autocomplete failed: %v", err)
	}
	if rt.calls != 1 {
		t.Fatalf("Google called %d times, want 1", rt.calls)
	}
	if c := svc.autocompleteCalls.snapshot(); c.Upstream != 1 || c.CacheHits != 1 {
		t.Fatalf("autocomplete counters = %+v, want upstream=1 cache_hits=1", c)
	}
}

// placesCallsSnapshot must price exactly the UPSTREAM counts (cache hits are
// free) with the per-class constants — the dashboard's est_places_cost_usd.
func TestPlacesCallsSnapshotPricing(t *testing.T) {
	svc := NewGooglePlacesService()
	svc.searchCalls.upstream.Add(1000)       // $32
	svc.searchCalls.cacheHits.Add(500)       // free
	svc.autocompleteCalls.upstream.Add(1000) // $2.83
	svc.detailsCalls.upstream.Add(1000)      // $17

	snap := placesCallsSnapshot(svc)
	if snap.Search.Upstream != 1000 || snap.Search.CacheHits != 500 {
		t.Fatalf("search snapshot = %+v", snap.Search)
	}
	want := 32.0 + 2.83 + 17.0
	if diff := snap.EstPlacesCostUSD - want; diff > 1e-9 || diff < -1e-9 {
		t.Fatalf("est_places_cost_usd = %v, want %v", snap.EstPlacesCostUSD, want)
	}
}

// Degraded mode: the process-wide singleton is constructed at init even when
// GOOGLE_PLACES_API_KEY is absent; methods must fail with a clear error, not
// panic, so the rest of the API stays healthy.
func TestPlacesServiceSingletonSafeWithoutKey(t *testing.T) {
	if placesService == nil {
		t.Fatal("placesService singleton is nil")
	}

	svc := NewGooglePlacesService()
	svc.APIKey = ""
	if _, err := svc.SearchPlaces("anything"); err == nil || !strings.Contains(err.Error(), "not configured") {
		t.Fatalf("SearchPlaces without key: err = %v, want not-configured error", err)
	}
	if _, err := svc.GetPlaceAutocomplete("any"); err == nil {
		t.Fatal("GetPlaceAutocomplete without key must error")
	}
	if _, err := svc.GetPlaceDetails("p1"); err == nil {
		t.Fatal("GetPlaceDetails without key must error")
	}
}

// failingTransport fails every round trip at the transport level, the way a
// DNS failure / upstream outage / client timeout does. http.Client wraps such
// failures in a *url.Error whose string embeds the full request URL — query
// secrets included — which is exactly what redactTransportError must strip.
type failingTransport struct{}

func (failingTransport) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, errFakeTransport
}

var errFakeTransport = fmt.Errorf("dial tcp 1.2.3.4:443: connection refused")

// Transport-level failures must never put the Google key (sent as a `key=`
// query param) into the error chain: these errors are surfaced to /plan tool
// results and, pre-redaction, were echoed by public handlers.
func TestPlacesTransportErrorsOmitAPIKey(t *testing.T) {
	const secret = "SECRET-GOOGLE-KEY"
	svc := NewGooglePlacesService()
	svc.APIKey = secret
	svc.Client = &http.Client{Transport: failingTransport{}}

	calls := []struct {
		name string
		call func() error
	}{
		{"SearchPlaces", func() error { _, err := svc.SearchPlaces("louvre"); return err }},
		{"GetPlaceAutocomplete", func() error { _, err := svc.GetPlaceAutocomplete("lou"); return err }},
		{"GetPlaceDetails", func() error { _, err := svc.GetPlaceDetails("p1"); return err }},
	}
	for _, c := range calls {
		err := c.call()
		if err == nil {
			t.Fatalf("%s: expected a transport error", c.name)
		}
		msg := err.Error()
		if strings.Contains(msg, secret) || strings.Contains(msg, "key=") {
			t.Fatalf("%s: error leaks the API key: %q", c.name, msg)
		}
		if !strings.Contains(msg, "connection refused") {
			t.Fatalf("%s: redaction lost the underlying cause: %q", c.name, msg)
		}
	}
}
