package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const fakeTicketmasterJSON = `{"_embedded":{"events":[{"id":"e1","name":"Test Show","url":"https://tickets.example/e1","dates":{"start":{"localDate":"2026-08-02","localTime":"19:00:00"}},"classifications":[{"segment":{"name":"Music"}}],"_embedded":{"venues":[{"name":"Test Hall","city":{"name":"Paris"},"location":{"latitude":"48.86","longitude":"2.34"}}]}}]}}`

func newTestEventsService(t *testing.T) (*EventsService, *int) {
	t.Helper()
	calls := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(fakeTicketmasterJSON))
	}))
	t.Cleanup(srv.Close)
	return &EventsService{
		APIKey:  "test-key",
		BaseURL: srv.URL,
		Client:  srv.Client(),
		cache:   newTTLCache[[]Event](eventsCacheTTL, 100),
	}, &calls
}

// The free Ticketmaster tier is 5 req/s / 5k per day: identical searches
// within the TTL must be served from memory, keyed on city+window+category
// (city case/whitespace-insensitively).
func TestSearchEventsServedFromCache(t *testing.T) {
	svc, calls := newTestEventsService(t)
	ctx := context.Background()

	first, err := svc.SearchEvents(ctx, "Paris", "2026-08-01", "2026-08-03", nil)
	if err != nil {
		t.Fatalf("first search failed: %v", err)
	}
	second, err := svc.SearchEvents(ctx, "  paris ", "2026-08-01", "2026-08-03", nil)
	if err != nil {
		t.Fatalf("second search failed: %v", err)
	}

	if *calls != 1 {
		t.Fatalf("Ticketmaster called %d times, want 1 (second lookup must come from cache)", *calls)
	}
	if len(first) != 1 || len(second) != 1 || second[0].ID != "e1" {
		t.Fatalf("cached result mismatch: first=%v second=%v", first, second)
	}
	// Quota-visibility counters mirror the traffic: one upstream, one hit.
	if c := svc.calls.snapshot(); c.Upstream != 1 || c.CacheHits != 1 {
		t.Fatalf("events counters = %+v, want upstream=1 cache_hits=1", c)
	}
}

func TestSearchEventsCacheKeyCoversInputs(t *testing.T) {
	svc, calls := newTestEventsService(t)
	ctx := context.Background()

	if _, err := svc.SearchEvents(ctx, "Paris", "2026-08-01", "2026-08-03", nil); err != nil {
		t.Fatalf("search failed: %v", err)
	}
	// A different category is a different result set — must not reuse the entry.
	cat := "music"
	if _, err := svc.SearchEvents(ctx, "Paris", "2026-08-01", "2026-08-03", &cat); err != nil {
		t.Fatalf("category search failed: %v", err)
	}
	// A different window likewise.
	if _, err := svc.SearchEvents(ctx, "Paris", "2026-08-02", "2026-08-03", nil); err != nil {
		t.Fatalf("window search failed: %v", err)
	}
	if *calls != 3 {
		t.Fatalf("Ticketmaster called %d times, want 3 (distinct inputs must not share entries)", *calls)
	}
}

func TestSearchEventsWithoutKeyErrors(t *testing.T) {
	svc, calls := newTestEventsService(t)
	svc.APIKey = ""
	if _, err := svc.SearchEvents(context.Background(), "Paris", "2026-08-01", "2026-08-03", nil); err == nil {
		t.Fatal("expected not-configured error without API key")
	}
	if *calls != 0 {
		t.Fatalf("Ticketmaster called %d times without a key, want 0", *calls)
	}
}

// Transport-level failures must never put the Ticketmaster key (an `apikey=`
// query param) into the error chain — eventsSearchHandler and the /plan
// agent's search_events tool both surface these error strings.
func TestSearchEventsTransportErrorOmitsAPIKey(t *testing.T) {
	const secret = "SECRET-TICKETMASTER-KEY"
	svc := &EventsService{
		APIKey:  secret,
		BaseURL: "https://app.ticketmaster.example/discovery/v2",
		Client:  &http.Client{Transport: failingTransport{}},
		cache:   newTTLCache[[]Event](eventsCacheTTL, 100),
	}
	_, err := svc.SearchEvents(context.Background(), "Paris", "2026-08-01", "2026-08-03", nil)
	if err == nil {
		t.Fatal("expected a transport error")
	}
	msg := err.Error()
	if strings.Contains(msg, secret) || strings.Contains(msg, "apikey=") {
		t.Fatalf("error leaks the API key: %q", msg)
	}
	if !strings.Contains(msg, "connection refused") {
		t.Fatalf("redaction lost the underlying cause: %q", msg)
	}
}
