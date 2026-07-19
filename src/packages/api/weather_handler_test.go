package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// A fake Open-Meteo: /v1/search geocodes (optionally empty), /v1/forecast and
// /v1/archive return a two-day daily series. Lets the handler test drive the
// real WeatherService end to end without hitting the network.
func newTestWeatherServer(t *testing.T, geocodeHit bool) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.Contains(r.URL.Path, "/search"):
			if !geocodeHit {
				w.Write([]byte(`{"results":[]}`))
				return
			}
			w.Write([]byte(`{"results":[{"name":"Paris","country":"France","latitude":48.85,"longitude":2.35}]}`))
		default: // forecast or archive
			w.Write([]byte(`{"daily":{"time":["2099-08-01","2099-08-02"],"temperature_2m_max":[26,28],"temperature_2m_min":[17,18],"precipitation_sum":[0,3],"precipitation_probability_mean":[10,60]}}`))
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

func withTestWeatherService(t *testing.T, geocodeHit bool) {
	t.Helper()
	srv := newTestWeatherServer(t, geocodeHit)
	prev := weatherService
	t.Cleanup(func() { weatherService = prev })
	weatherService = &WeatherService{
		GeocodeBaseURL:  srv.URL,
		ForecastBaseURL: srv.URL,
		ArchiveBaseURL:  srv.URL,
		Client:          srv.Client(),
		geoCache:        newTTLCache[geoResult](time.Hour, 10),
		summaryCache:    newTTLCache[WeatherReport](time.Hour, 10),
	}
}

func TestWeatherHandlerMissingParams(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/api/v1/weather?start_date=2099-08-01", nil)
	rec := httptest.NewRecorder()
	weatherSearchHandler(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for missing city, got %d", rec.Code)
	}
}

func TestWeatherHandlerReturnsReport(t *testing.T) {
	withTestWeatherService(t, true)
	// A far-future range so the archive ("historical") branch runs deterministically.
	req := httptest.NewRequest(http.MethodGet, "/api/v1/weather?city=Paris&start_date=2099-08-01&end_date=2099-08-02", nil)
	rec := httptest.NewRecorder()
	weatherSearchHandler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
	}
	var report WeatherReport
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(report.Days) != 2 {
		t.Fatalf("expected 2 days, got %d", len(report.Days))
	}
	if report.Location == "" {
		t.Fatalf("expected a resolved location label")
	}
}

func TestWeatherHandlerGeocodeMissIsEmptyNot500(t *testing.T) {
	withTestWeatherService(t, false)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/weather?city=Nowheresville&start_date=2099-08-01", nil)
	rec := httptest.NewRecorder()
	weatherSearchHandler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected best-effort 200 on geocode miss, got %d", rec.Code)
	}
	var report WeatherReport
	if err := json.Unmarshal(rec.Body.Bytes(), &report); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(report.Days) != 0 {
		t.Fatalf("expected empty report, got %d days", len(report.Days))
	}
}
