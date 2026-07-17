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

// Mid-trip queries (start date already past) must still use the real
// forecast for the remaining days, clamped to today — not last year's data.
func TestGetTripWeatherMidTripUsesForecast(t *testing.T) {
	s, paths := stubWeather(t)
	start := time.Now().AddDate(0, 0, -3).Format(dateLayout)
	end := time.Now().AddDate(0, 0, 4).Format(dateLayout)

	report, err := s.GetTripWeather(context.Background(), "Athens", start, end)
	if err != nil {
		t.Fatalf("GetTripWeather: %v", err)
	}
	if report.Kind != "forecast" {
		t.Fatalf("mid-trip kind = %s, want forecast", report.Kind)
	}
	for _, p := range *paths {
		if strings.HasPrefix(p, "/v1/archive") {
			t.Fatal("mid-trip query hit the archive API")
		}
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
	msg, isErr := runGetTripTool(context.Background(), false, uuid.Nil, nil, json.RawMessage(`{}`))
	if !isErr || !strings.Contains(msg, "not signed in") {
		t.Fatalf("anonymous get_trip = %q (err=%v)", msg, isErr)
	}
}

// testPlanSession builds the minimal session the booking-todo dispatchers
// need; the recorder doubles as the SSE sink so tests can assert side events.
func testPlanSession(authed bool, uid uuid.UUID) (*planSession, *httptest.ResponseRecorder) {
	rec := httptest.NewRecorder()
	return &planSession{ctx: context.Background(), w: rec, authed: authed, uid: uid}, rec
}

func TestBookingTodoToolsAnonymous(t *testing.T) {
	s, _ := testPlanSession(false, uuid.Nil)
	for name, run := range map[string]func(*planSession, json.RawMessage) (string, bool){
		"add_booking_todo":    runAddBookingTodoTool,
		"update_booking_todo": runUpdateBookingTodoTool,
		"remove_booking_todo": runRemoveBookingTodoTool,
	} {
		msg, isErr := run(s, json.RawMessage(`{}`))
		if !isErr || !strings.Contains(msg, "not signed in") {
			t.Fatalf("anonymous %s = %q (err=%v)", name, msg, isErr)
		}
	}
}

func TestGetTripToolListsAndReads(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "agent@example.com")
	other, _ := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	createTestTrip(t, other.ID, 1) // must never appear for owner

	list, isErr := runGetTripTool(context.Background(), true, owner.ID, nil, json.RawMessage(`{}`))
	if isErr || !strings.Contains(list, trip.ID.String()) || !strings.Contains(list, "saved trips (1)") {
		t.Fatalf("list = %q (err=%v)", list, isErr)
	}

	detail, isErr := runGetTripTool(context.Background(), true, owner.ID, nil,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`"}`))
	if isErr || !strings.Contains(detail, "Place 1") || !strings.Contains(detail, "2 places") {
		t.Fatalf("detail = %q (err=%v)", detail, isErr)
	}

	// Cross-user read must fail closed.
	_, isErr = runGetTripTool(context.Background(), true, other.ID, nil,
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

	s, rec := testPlanSession(true, owner.ID)
	msg, isErr := runAddBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","kind":"transport","title":"Book Blue Star ferry"}`))
	if isErr || !strings.Contains(msg, "Book Blue Star ferry") {
		t.Fatalf("add = %q (err=%v)", msg, isErr)
	}
	if !strings.Contains(rec.Body.String(), "trip_updated") {
		t.Fatal("add_booking_todo did not emit trip_updated")
	}

	// Visible through the regular API for the owner.
	get := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil)
	if get.Code != http.StatusOK || !strings.Contains(get.Body.String(), "Book Blue Star ferry") {
		t.Fatalf("todo not on trip: %d %s", get.Code, get.Body.String())
	}

	// Cross-user write must fail closed.
	otherS, _ := testPlanSession(true, other.ID)
	_, isErr = runAddBookingTodoTool(otherS,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","kind":"other","title":"Hijack"}`))
	if !isErr {
		t.Fatal("cross-user add_booking_todo did not error")
	}

	// Bad kind rejected.
	if _, isErr := runAddBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","kind":"spa","title":"x"}`)); !isErr {
		t.Fatal("invalid kind accepted")
	}
}

// seedAgentTodo adds an agent booking todo to the trip and returns its id.
func seedAgentTodo(t *testing.T, s *planSession, tripID uuid.UUID, title string) uuid.UUID {
	t.Helper()
	if msg, isErr := runAddBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+tripID.String()+`","kind":"transport","title":"`+title+`"}`)); isErr {
		t.Fatalf("seed todo: %q", msg)
	}
	var id uuid.UUID
	if err := dbPool.QueryRow(context.Background(),
		`SELECT id FROM booking_todos WHERE trip_id = $1 AND title = $2`, tripID, title).Scan(&id); err != nil {
		t.Fatalf("seeded todo not found: %v", err)
	}
	return id
}

// seedAutoTodo inserts an itinerary-synced (auto=true) row directly.
func seedAutoTodo(t *testing.T, tripID uuid.UUID) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	if err := dbPool.QueryRow(context.Background(),
		`INSERT INTO booking_todos (trip_id, kind, todo_key, title, auto, position)
		 VALUES ($1, 'stay', 'stay:testville', 'Stay in Testville', true, 0) RETURNING id`,
		tripID).Scan(&id); err != nil {
		t.Fatalf("seed auto todo: %v", err)
	}
	return id
}

func TestUpdateBookingTodoToolPartialUpdate(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "agent@example.com")
	other, _ := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	s, rec := testPlanSession(true, owner.ID)
	todoID := seedAgentTodo(t, s, trip.ID, "Book flights EWR to CUR")

	msg, isErr := runUpdateBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+todoID.String()+`","title":"Book flights EWR to MIA","booked":true}`))
	if isErr || !strings.Contains(msg, "Book flights EWR to MIA") {
		t.Fatalf("update = %q (err=%v)", msg, isErr)
	}
	if !strings.Contains(rec.Body.String(), "trip_updated") {
		t.Fatal("update_booking_todo did not emit trip_updated")
	}

	// Title and booked changed; untouched fields (kind) survive.
	get := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil)
	body := get.Body.String()
	if !strings.Contains(body, "Book flights EWR to MIA") || strings.Contains(body, "EWR to CUR") {
		t.Fatalf("title not updated: %s", body)
	}
	if !strings.Contains(body, `"booked":true`) || !strings.Contains(body, `"kind":"transport"`) {
		t.Fatalf("partial update clobbered fields: %s", body)
	}

	// Cross-user update must fail closed.
	otherS, _ := testPlanSession(true, other.ID)
	if _, isErr := runUpdateBookingTodoTool(otherS,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+todoID.String()+`","title":"Hijack"}`)); !isErr {
		t.Fatal("cross-user update_booking_todo did not error")
	}

	// Bad kind, empty title, no fields, unknown id — all rejected.
	for name, input := range map[string]string{
		"invalid kind": `{"trip_id":"` + trip.ID.String() + `","todo_id":"` + todoID.String() + `","kind":"spa"}`,
		"empty title":  `{"trip_id":"` + trip.ID.String() + `","todo_id":"` + todoID.String() + `","title":"  "}`,
		"no fields":    `{"trip_id":"` + trip.ID.String() + `","todo_id":"` + todoID.String() + `"}`,
		"unknown id":   `{"trip_id":"` + trip.ID.String() + `","todo_id":"` + uuid.NewString() + `","title":"x"}`,
	} {
		if _, isErr := runUpdateBookingTodoTool(s, json.RawMessage(input)); !isErr {
			t.Fatalf("%s accepted", name)
		}
	}
}

func TestRemoveBookingTodoTool(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "agent@example.com")
	other, _ := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	s, rec := testPlanSession(true, owner.ID)
	todoID := seedAgentTodo(t, s, trip.ID, "Book flights EWR to CUR")

	// Cross-user remove must fail closed (and leave the row).
	otherS, _ := testPlanSession(true, other.ID)
	if _, isErr := runRemoveBookingTodoTool(otherS,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+todoID.String()+`"}`)); !isErr {
		t.Fatal("cross-user remove_booking_todo did not error")
	}

	msg, isErr := runRemoveBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+todoID.String()+`"}`))
	if isErr {
		t.Fatalf("remove = %q (err=%v)", msg, isErr)
	}
	if !strings.Contains(rec.Body.String(), "trip_updated") {
		t.Fatal("remove_booking_todo did not emit trip_updated")
	}
	get := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil)
	if strings.Contains(get.Body.String(), "EWR to CUR") {
		t.Fatalf("todo still on trip: %s", get.Body.String())
	}

	// Removing again reports the friendly miss.
	if msg, isErr := runRemoveBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+todoID.String()+`"}`)); !isErr || !strings.Contains(msg, "No such checklist item") {
		t.Fatalf("double remove = %q (err=%v)", msg, isErr)
	}
}

func TestBookingTodoToolsRefuseAutoRows(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "agent@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	autoID := seedAutoTodo(t, trip.ID)
	s, _ := testPlanSession(true, owner.ID)

	if msg, isErr := runUpdateBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+autoID.String()+`","title":"Overwrite"}`)); !isErr || !strings.Contains(msg, "auto") {
		t.Fatalf("auto row updated: %q (err=%v)", msg, isErr)
	}
	if msg, isErr := runRemoveBookingTodoTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","todo_id":"`+autoID.String()+`"}`)); !isErr || !strings.Contains(msg, "auto") {
		t.Fatalf("auto row removed: %q (err=%v)", msg, isErr)
	}
	var n int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*) FROM booking_todos WHERE id = $1`, autoID).Scan(&n); err != nil || n != 1 {
		t.Fatalf("auto row gone (n=%d, err=%v)", n, err)
	}
}

func TestGetTripToolShowsBookingChecklist(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "agent@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	s, _ := testPlanSession(true, owner.ID)
	todoID := seedAgentTodo(t, s, trip.ID, "Book flights EWR to CUR")
	seedAutoTodo(t, trip.ID)

	detail, isErr := runGetTripTool(context.Background(), true, owner.ID, nil,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`"}`))
	if isErr {
		t.Fatalf("detail errored: %q", detail)
	}
	if !strings.Contains(detail, "Booking checklist (2 items)") ||
		!strings.Contains(detail, "todo_id: "+todoID.String()) ||
		!strings.Contains(detail, "agent-added") {
		t.Fatalf("checklist missing from detail:\n%s", detail)
	}
	if !strings.Contains(detail, "auto — tracks the itinerary; not editable") {
		t.Fatalf("auto marker missing from detail:\n%s", detail)
	}
}
