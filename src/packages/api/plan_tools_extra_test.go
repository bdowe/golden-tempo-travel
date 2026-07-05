package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// stubWeather wires a WeatherService whose geocode/forecast/archive endpoints
// all answer from one httptest server.
func stubWeather(t *testing.T) (*WeatherService, *[]string) {
	t.Helper()
	var paths []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		paths = append(paths, r.URL.Path)
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.HasPrefix(r.URL.Path, "/v1/search"):
			fmt.Fprint(w, `{"results":[{"name":"Athens","country":"Greece","latitude":37.98,"longitude":23.72}]}`)
		case strings.HasPrefix(r.URL.Path, "/v1/forecast"):
			fmt.Fprint(w, `{"daily":{"time":["2026-07-10","2026-07-11"],
				"temperature_2m_max":[33.1,34.0],"temperature_2m_min":[24.2,25.0],
				"precipitation_sum":[0,2.4],"precipitation_probability_mean":[5,40]}}`)
		case strings.HasPrefix(r.URL.Path, "/v1/archive"):
			fmt.Fprint(w, `{"daily":{"time":["2025-10-01"],
				"temperature_2m_max":[26.5],"temperature_2m_min":[18.1],
				"precipitation_sum":[3.2]}}`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	s := NewWeatherService()
	s.GeocodeBaseURL = srv.URL
	s.ForecastBaseURL = srv.URL
	s.ArchiveBaseURL = srv.URL
	return s, &paths
}

func TestGetTripWeatherForecastPath(t *testing.T) {
	s, _ := stubWeather(t)
	start := time.Now().AddDate(0, 0, 3).Format(dateLayout)
	end := time.Now().AddDate(0, 0, 4).Format(dateLayout)

	report, err := s.GetTripWeather(context.Background(), "Athens", start, end)
	if err != nil {
		t.Fatalf("GetTripWeather: %v", err)
	}
	if report.Kind != "forecast" || report.Location != "Athens, Greece" || len(report.Days) != 2 {
		t.Fatalf("report = %+v", report)
	}
	if report.Days[1].PrecipPct == nil || *report.Days[1].PrecipPct != 40 {
		t.Fatalf("forecast day missing precip probability: %+v", report.Days[1])
	}

	text := summarizeWeather(report)
	if !strings.Contains(text, "Forecast for Athens, Greece") || !strings.Contains(text, "40% chance of rain") {
		t.Fatalf("summary wrong:\n%s", text)
	}
}

func TestGetTripWeatherFallsBackToArchive(t *testing.T) {
	s, paths := stubWeather(t)
	// Far beyond the 16-day horizon → last year's observations.
	start := time.Now().AddDate(0, 3, 0).Format(dateLayout)

	report, err := s.GetTripWeather(context.Background(), "Athens", start, "")
	if err != nil {
		t.Fatalf("GetTripWeather: %v", err)
	}
	if report.Kind != "historical" {
		t.Fatalf("kind = %s, want historical", report.Kind)
	}
	var hitArchive bool
	for _, p := range *paths {
		if strings.HasPrefix(p, "/v1/archive") {
			hitArchive = true
		}
		if strings.HasPrefix(p, "/v1/forecast") {
			t.Fatal("far-out dates must not hit the forecast API")
		}
	}
	if !hitArchive {
		t.Fatal("archive API was not called")
	}
	if !strings.Contains(summarizeWeather(report), "Typical weather") {
		t.Fatal("historical summary must be framed as typical, not a forecast")
	}
}

func TestGetTripWeatherCaches(t *testing.T) {
	s, paths := stubWeather(t)
	start := time.Now().AddDate(0, 0, 3).Format(dateLayout)
	if _, err := s.GetTripWeather(context.Background(), "Athens", start, ""); err != nil {
		t.Fatal(err)
	}
	n := len(*paths)
	if _, err := s.GetTripWeather(context.Background(), "Athens", start, ""); err != nil {
		t.Fatal(err)
	}
	if len(*paths) != n {
		t.Fatalf("second identical lookup hit the network (%d -> %d calls)", n, len(*paths))
	}
}

func TestGetTripToolAnonymous(t *testing.T) {
	msg, isErr := runGetTripTool(context.Background(), false, uuid.Nil, json.RawMessage(`{}`))
	if !isErr || !strings.Contains(msg, "not signed in") {
		t.Fatalf("anonymous get_trip = %q (err=%v)", msg, isErr)
	}
}

func TestAddBookingTodoToolAnonymous(t *testing.T) {
	msg, isErr := runAddBookingTodoTool(context.Background(), false, uuid.Nil, json.RawMessage(`{}`))
	if !isErr || !strings.Contains(msg, "not signed in") {
		t.Fatalf("anonymous add_booking_todo = %q (err=%v)", msg, isErr)
	}
}

func TestGetTripToolListsAndReads(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "agent@example.com")
	other, _ := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	createTestTrip(t, other.ID, 1) // must never appear for owner

	list, isErr := runGetTripTool(context.Background(), true, owner.ID, json.RawMessage(`{}`))
	if isErr || !strings.Contains(list, trip.ID.String()) || !strings.Contains(list, "saved trips (1)") {
		t.Fatalf("list = %q (err=%v)", list, isErr)
	}

	detail, isErr := runGetTripTool(context.Background(), true, owner.ID,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`"}`))
	if isErr || !strings.Contains(detail, "Place 1") || !strings.Contains(detail, "2 places") {
		t.Fatalf("detail = %q (err=%v)", detail, isErr)
	}

	// Cross-user read must fail closed.
	_, isErr = runGetTripTool(context.Background(), true, other.ID,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`"}`))
	if !isErr {
		t.Fatal("cross-user get_trip did not error")
	}
}

func TestAddBookingTodoToolWritesOwnedTripOnly(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "agent@example.com")
	other, _ := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	msg, isErr := runAddBookingTodoTool(context.Background(), true, owner.ID,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","kind":"transport","title":"Book Blue Star ferry"}`))
	if isErr || !strings.Contains(msg, "Book Blue Star ferry") {
		t.Fatalf("add = %q (err=%v)", msg, isErr)
	}

	// Visible through the regular API for the owner.
	rec := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Book Blue Star ferry") {
		t.Fatalf("todo not on trip: %d %s", rec.Code, rec.Body.String())
	}

	// Cross-user write must fail closed.
	_, isErr = runAddBookingTodoTool(context.Background(), true, other.ID,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","kind":"other","title":"Hijack"}`))
	if !isErr {
		t.Fatal("cross-user add_booking_todo did not error")
	}

	// Bad kind rejected.
	if _, isErr := runAddBookingTodoTool(context.Background(), true, owner.ID,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","kind":"spa","title":"x"}`)); !isErr {
		t.Fatal("invalid kind accepted")
	}
}
