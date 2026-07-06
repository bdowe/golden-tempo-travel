package main

import (
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
