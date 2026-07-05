package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// stubDuffel captures the offer-request payload the service sends.
func stubDuffel(t *testing.T, captured *map[string]any) *DuffelService {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		if err := json.Unmarshal(body, captured); err != nil {
			t.Fatalf("stub could not parse request body: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"data":{"offers":[]}}`))
	}))
	t.Cleanup(srv.Close)
	return &DuffelService{
		Token:   "test-token",
		BaseURL: srv.URL,
		Version: "v2",
		Client:  &http.Client{Timeout: 5 * time.Second},
	}
}

func TestSearchFlightOffersPassengerAndCabinPayload(t *testing.T) {
	var captured map[string]any
	d := stubDuffel(t, &captured)

	_, err := d.SearchFlightOffers(context.Background(), FlightSearchRequest{
		Origin: "bos", Destination: "cdg", DepartDate: "2026-09-01",
		Adults: 2, ChildAges: []int{5, 9}, CabinClass: "Business",
	})
	if err != nil {
		t.Fatalf("SearchFlightOffers: %v", err)
	}

	data := captured["data"].(map[string]any)
	if got := data["cabin_class"]; got != "business" {
		t.Fatalf("cabin_class = %v, want business (lowercased)", got)
	}
	passengers := data["passengers"].([]any)
	if len(passengers) != 4 {
		t.Fatalf("passengers = %d, want 4 (2 adults + 2 children)", len(passengers))
	}
	adults, children := 0, 0
	for _, p := range passengers {
		pm := p.(map[string]any)
		switch {
		case pm["type"] == "adult":
			adults++
		case pm["age"] != nil:
			children++
			if _, hasType := pm["type"]; hasType {
				t.Fatal("child passenger must not carry a type field")
			}
		default:
			t.Fatalf("unexpected passenger entry: %v", pm)
		}
	}
	if adults != 2 || children != 2 {
		t.Fatalf("adults=%d children=%d, want 2/2", adults, children)
	}
}

func TestSearchFlightOffersDefaultsToEconomy(t *testing.T) {
	var captured map[string]any
	d := stubDuffel(t, &captured)

	if _, err := d.SearchFlightOffers(context.Background(), FlightSearchRequest{
		Origin: "BOS", Destination: "CDG", DepartDate: "2026-09-01", Adults: 1,
	}); err != nil {
		t.Fatalf("SearchFlightOffers: %v", err)
	}
	data := captured["data"].(map[string]any)
	if got := data["cabin_class"]; got != "economy" {
		t.Fatalf("cabin_class = %v, want economy default", got)
	}
	if got := len(data["passengers"].([]any)); got != 1 {
		t.Fatalf("passengers = %d, want 1", got)
	}
}
