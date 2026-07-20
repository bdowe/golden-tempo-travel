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
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// Pure unit tests for the individual review checks — hand-built exportData, no
// DB. These exercise the deterministic rules in isolation.

func dateVal(t *testing.T, s string) pgtype.Date {
	t.Helper()
	tm, err := time.Parse("2006-01-02", s)
	if err != nil {
		t.Fatalf("parse date %q: %v", s, err)
	}
	return pgtype.Date{Time: tm, Valid: true}
}

func i32p(v int32) *int32 { return &v }

func TestCheckDates_Undated(t *testing.T) {
	d := exportData{Trip: store.Trip{ID: uuid.New(), Status: "draft"}}
	fs := checkDates(d)
	if len(fs) != 1 || fs[0].Category != "dates" || fs[0].Severity != "info" {
		t.Fatalf("undated trip = %+v", fs)
	}
}

func TestCheckDates_ItemPastSpan(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03")} // 3-day span
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Louvre", Day: i32p(2)},
		{ID: uuid.New(), Name: "Way Out", Day: i32p(9)},
	}
	fs := checkDates(exportData{Trip: trip, Items: items})
	if len(fs) != 1 || fs[0].Severity != "warn" || fs[0].Day == nil || *fs[0].Day != 9 {
		t.Fatalf("past-span = %+v", fs)
	}
}

func TestCheckUnscheduled_Grouped(t *testing.T) {
	d := exportData{Trip: store.Trip{ID: uuid.New()}, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "A"}, // day nil
		{ID: uuid.New(), Name: "B"}, // day nil
		{ID: uuid.New(), Name: "C", Day: i32p(1)},
	}}
	fs := checkUnscheduled(d)
	if len(fs) != 1 || fs[0].Category != "unscheduled" {
		t.Fatalf("unscheduled = %+v", fs)
	}
}

func TestCheckDensity_EmptyAndPacked(t *testing.T) {
	morning := strp("morning")
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "A", Day: i32p(1), TimeOfDay: morning},
		{ID: uuid.New(), Name: "B", Day: i32p(1), TimeOfDay: morning}, // two mornings on day 1
		// day 2 empty
		{ID: uuid.New(), Name: "C", Day: i32p(3)},
	}
	fs := checkDensity(exportData{Trip: store.Trip{ID: uuid.New()}, Items: items})
	cats := map[string][]Finding{}
	for _, f := range fs {
		cats[f.Severity] = append(cats[f.Severity], f)
	}
	if len(cats["info"]) != 1 { // day 2 empty
		t.Fatalf("expected one empty-day info, got %+v", fs)
	}
	if len(cats["warn"]) != 1 { // two mornings day 1
		t.Fatalf("expected one over-packed warn, got %+v", fs)
	}
}

func TestCheckLodging_GateAndCoverage(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-04")} // 3 nights: 1,2,3

	// No accommodations, planned → all 3 nights flagged.
	fs := checkLodging(exportData{Trip: trip})
	if len(fs) != 3 {
		t.Fatalf("planned no-lodging = %d findings, want 3: %+v", len(fs), fs)
	}

	// One stay covering nights 1-2 (checkout 08-03, exclusive) → only night 3 flagged.
	acc := []store.Accommodation{{ID: uuid.New(), Name: "Hotel",
		CheckIn: dateVal(t, "2026-08-01"), CheckOut: dateVal(t, "2026-08-03")}}
	fs = checkLodging(exportData{Trip: trip, Accommodations: acc})
	if len(fs) != 1 || fs[0].Day == nil || *fs[0].Day != 3 {
		t.Fatalf("partial lodging = %+v", fs)
	}

	// Empty draft (draft status, no accommodations) is not nagged.
	draft := trip
	draft.Status = "draft"
	if fs := checkLodging(exportData{Trip: draft}); len(fs) != 0 {
		t.Fatalf("empty draft should be silent, got %+v", fs)
	}
}

func TestCheckTransit_MissingLeg(t *testing.T) {
	trip := store.Trip{ID: uuid.New()}
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Colosseum", City: strp("Rome"), Day: i32p(1)},
		{ID: uuid.New(), Name: "Duomo", City: strp("Florence"), Day: i32p(2)},
	}
	// No segments → missing Rome→Florence leg.
	fs := checkTransit(exportData{Trip: trip, Items: items})
	if len(fs) != 1 || fs[0].Category != "transit" {
		t.Fatalf("missing leg = %+v", fs)
	}
	// A connecting segment suppresses it.
	segs := []store.TripSegment{{ID: uuid.New(), Mode: "train",
		Origin: strp("Rome"), Destination: strp("Florence")}}
	if fs := checkTransit(exportData{Trip: trip, Items: items, Segments: segs}); len(fs) != 0 {
		t.Fatalf("connected legs should be silent, got %+v", fs)
	}
}

func TestCheckBudget_OverBudget(t *testing.T) {
	over := -50.0
	br := &BudgetResponse{Currency: "USD", Spent: 150, Remaining: &over}
	fs := checkBudget(exportData{Trip: store.Trip{ID: uuid.New()}}, br)
	if len(fs) != 1 || fs[0].Category != "budget" || fs[0].Severity != "warn" {
		t.Fatalf("over budget = %+v", fs)
	}
	within := 10.0
	if fs := checkBudget(exportData{Trip: store.Trip{ID: uuid.New()}}, &BudgetResponse{Remaining: &within}); len(fs) != 0 {
		t.Fatalf("within budget should be silent, got %+v", fs)
	}
	if fs := checkBudget(exportData{Trip: store.Trip{ID: uuid.New()}}, nil); len(fs) != 0 {
		t.Fatalf("no budget should be silent, got %+v", fs)
	}
}

func TestCheckBookings_Unbooked(t *testing.T) {
	d := exportData{
		Trip: store.Trip{ID: uuid.New()},
		Accommodations: []store.Accommodation{
			{ID: uuid.New(), Name: "Hotel", Booked: false},
			{ID: uuid.New(), Name: "Booked Inn", Booked: true},
			// Auto "Suggested" draft — a system suggestion, not a user booking.
			{ID: uuid.New(), Name: "Suggested Stay", Booked: false, Auto: true},
		},
		Segments: []store.TripSegment{
			{ID: uuid.New(), Mode: "flight", Origin: strp("JFK"), Destination: strp("CDG"), Booked: false},
			// Auto suggested segment — also skipped.
			{ID: uuid.New(), Mode: "train", Origin: strp("Rome"), Destination: strp("Florence"), Booked: false, Auto: true},
		},
	}
	fs := checkBookings(d)
	if len(fs) != 2 {
		t.Fatalf("expected 2 unbooked findings (auto drafts skipped), got %+v", fs)
	}
	for _, f := range fs {
		if f.Severity != "info" || f.Category != "bookings" || f.ItemID == nil {
			t.Fatalf("booking finding shape = %+v", f)
		}
		if strings.Contains(f.Message, "Suggested") {
			t.Fatalf("auto suggestion should not be flagged: %+v", f)
		}
	}
}

// weatherStub serves geocode + forecast/archive from one httptest server,
// echoing the requested date range with caller-chosen conditions.
func weatherStub(t *testing.T, rainy bool, tempMax, tempMin float64) *WeatherService {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case strings.HasPrefix(r.URL.Path, "/v1/search"):
			fmt.Fprint(w, `{"results":[{"name":"Paris","country":"France","latitude":48.85,"longitude":2.35}]}`)
		case strings.HasPrefix(r.URL.Path, "/v1/forecast"), strings.HasPrefix(r.URL.Path, "/v1/archive"):
			q := r.URL.Query()
			start, _ := time.Parse(dateLayout, q.Get("start_date"))
			end, _ := time.Parse(dateLayout, q.Get("end_date"))
			forecast := strings.HasPrefix(r.URL.Path, "/v1/forecast")
			prob := 5
			psum := 0.0
			if rainy {
				prob, psum = 85, 9.0
			}
			var times, tmax, tmin, sum, pr []string
			for dt := start; !dt.After(end); dt = dt.AddDate(0, 0, 1) {
				times = append(times, `"`+dt.Format(dateLayout)+`"`)
				tmax = append(tmax, fmt.Sprintf("%f", tempMax))
				tmin = append(tmin, fmt.Sprintf("%f", tempMin))
				sum = append(sum, fmt.Sprintf("%f", psum))
				pr = append(pr, fmt.Sprintf("%d", prob))
			}
			out := fmt.Sprintf(`{"daily":{"time":[%s],"temperature_2m_max":[%s],"temperature_2m_min":[%s],"precipitation_sum":[%s]`,
				strings.Join(times, ","), strings.Join(tmax, ","), strings.Join(tmin, ","), strings.Join(sum, ","))
			if forecast {
				out += fmt.Sprintf(`,"precipitation_probability_mean":[%s]`, strings.Join(pr, ","))
			}
			out += "}}"
			fmt.Fprint(w, out)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	s := NewWeatherService()
	s.GeocodeBaseURL = srv.URL
	s.ForecastBaseURL = srv.URL
	s.ArchiveBaseURL = srv.URL
	return s
}

func TestCheckWeather_RainyOutdoorDay(t *testing.T) {
	// A dated future trip so the forecast path is used; day 1 has an outdoor
	// attraction in Paris.
	start := time.Now().AddDate(0, 0, 3)
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: pgtype.Date{Time: start.Truncate(24 * time.Hour), Valid: true},
		EndDate:   pgtype.Date{Time: start.AddDate(0, 0, 1).Truncate(24 * time.Hour), Valid: true}}
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Eiffel Tower", City: strp("Paris"), Category: strp("attraction"), Day: i32p(1)},
	}
	d := exportData{Trip: trip, Items: items}

	weather := weatherStub(t, true, 22, 14) // rainy, mild
	fs := checkWeather(context.Background(), d, weather)
	var gotRain bool
	for _, f := range fs {
		if f.Category != "weather" || f.Severity != "info" {
			t.Fatalf("weather finding shape = %+v", f)
		}
		if strings.Contains(f.Message, "umbrella") && f.Day != nil && *f.Day == 1 {
			gotRain = true
		}
	}
	if !gotRain {
		t.Fatalf("expected a Day 1 umbrella finding, got %+v", fs)
	}

	// Indoor-only day: same rain, but a museum → no umbrella nag.
	indoor := exportData{Trip: trip, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "Louvre", City: strp("Paris"), Category: strp("museum"), Day: i32p(1)},
	}}
	for _, f := range checkWeather(context.Background(), indoor, weather) {
		if strings.Contains(f.Message, "umbrella") {
			t.Fatalf("indoor day should not get an umbrella finding: %+v", f)
		}
	}

	// Nil service is a silent no-op.
	if fs := checkWeather(context.Background(), d, nil); len(fs) != 0 {
		t.Fatalf("nil weather service should yield no findings, got %+v", fs)
	}
}

func TestCheckWeather_HotDay(t *testing.T) {
	start := time.Now().AddDate(0, 0, 3)
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: pgtype.Date{Time: start.Truncate(24 * time.Hour), Valid: true},
		EndDate:   pgtype.Date{Time: start.Truncate(24 * time.Hour), Valid: true}}
	d := exportData{Trip: trip, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "Louvre", City: strp("Paris"), Category: strp("museum"), Day: i32p(1)},
	}}
	weather := weatherStub(t, false, 37, 26) // hot, dry
	var gotHot bool
	for _, f := range checkWeather(context.Background(), d, weather) {
		if strings.Contains(f.Message, "very hot") {
			gotHot = true
		}
	}
	if !gotHot {
		t.Fatal("expected a 'very hot' weather finding")
	}
}

// placesDouble builds a GooglePlacesService whose HTTP client answers every
// request from one canned body (via the shared countingTransport), counting
// billable calls so checkHours can be exercised without real Google.
func placesDouble(t *testing.T, body string) (*GooglePlacesService, *countingTransport) {
	t.Helper()
	rt := &countingTransport{body: body}
	svc := NewGooglePlacesService()
	svc.APIKey = "test-key"
	svc.Client = &http.Client{Transport: rt}
	return svc, rt
}

// closedMondayDetailsJSON: place open Tue–Sun, closed Monday.
const closedMondayDetailsJSON = `{"status":"OK","result":{"place_id":"p1","name":"Musée Rodin","formatted_address":"Paris","geometry":{"location":{"lat":48.85,"lng":2.31}},"types":["museum"],"opening_hours":{"open_now":false,"weekday_text":["Monday: Closed","Tuesday: 10:00 AM – 6:30 PM","Wednesday: 10:00 AM – 6:30 PM","Thursday: 10:00 AM – 6:30 PM","Friday: 10:00 AM – 6:30 PM","Saturday: 10:00 AM – 6:30 PM","Sunday: 10:00 AM – 6:30 PM"]}}}`

func TestCheckHours_ClosedOnScheduledWeekday(t *testing.T) {
	// 2026-08-03 is a Monday; the item scheduled to Day 1 lands on it.
	monday := dateVal(t, "2026-08-03")
	if monday.Time.Weekday() != time.Monday {
		t.Fatalf("fixture date is %s, expected Monday", monday.Time.Weekday())
	}
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: monday, EndDate: dateVal(t, "2026-08-04")}
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Musée Rodin", PlaceID: strp("p1"), Day: i32p(1)},
		{ID: uuid.New(), Name: "No PlaceID", Day: i32p(1)}, // skipped (no place_id)
	}
	d := exportData{Trip: trip, Items: items}

	svc, rt := placesDouble(t, closedMondayDetailsJSON)
	fs := checkHours(context.Background(), d, svc)
	if len(fs) != 1 || fs[0].Category != "hours" || fs[0].Severity != "warn" {
		t.Fatalf("expected one closed-weekday warn, got %+v", fs)
	}
	if !strings.Contains(fs[0].Message, "closed on Monday") {
		t.Fatalf("message = %q", fs[0].Message)
	}
	if rt.calls != 1 {
		t.Fatalf("expected exactly 1 place-details call (item without place_id skipped), got %d", rt.calls)
	}

	// Nil service is a silent no-op.
	if fs := checkHours(context.Background(), d, nil); len(fs) != 0 {
		t.Fatalf("nil places service should yield no findings, got %+v", fs)
	}
}

func TestReviewTrip_CheckHoursGate(t *testing.T) {
	monday := dateVal(t, "2026-08-03")
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: monday, EndDate: dateVal(t, "2026-08-04")}
	d := exportData{Trip: trip, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "Musée Rodin", PlaceID: strp("p1"), Day: i32p(1)},
	}}
	svc, rt := placesDouble(t, closedMondayDetailsJSON)
	deps := reviewDeps{Places: svc}

	// CheckHours=false → the hours check never runs (no Google call, no hours finding).
	for _, f := range reviewTrip(context.Background(), d, reviewOptions{CheckHours: false}, deps) {
		if f.Category == "hours" {
			t.Fatalf("hours finding leaked with CheckHours=false: %+v", f)
		}
	}
	if rt.calls != 0 {
		t.Fatalf("CheckHours=false must not call Google, got %d calls", rt.calls)
	}

	// CheckHours=true → the finding appears.
	var gotHours bool
	for _, f := range reviewTrip(context.Background(), d, reviewOptions{CheckHours: true}, deps) {
		if f.Category == "hours" {
			gotHours = true
		}
	}
	if !gotHours {
		t.Fatal("expected an hours finding with CheckHours=true")
	}
}

// --- structured fix descriptors (Wave 19 PR1) --------------------------------

func TestFix_Lodging(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-04")} // nights 1,2,3
	// One stay covering nights 1-2 → only night 3 (Day 3 = 2026-08-03) flagged.
	acc := []store.Accommodation{{ID: uuid.New(), Name: "Hotel",
		CheckIn: dateVal(t, "2026-08-01"), CheckOut: dateVal(t, "2026-08-03")}}
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Beach", City: strp("Nice"), Day: i32p(3)},
	}
	fs := checkLodging(exportData{Trip: trip, Accommodations: acc, Items: items})
	if len(fs) != 1 || fs[0].Fix == nil {
		t.Fatalf("expected one lodging finding with a fix, got %+v", fs)
	}
	fix := fs[0].Fix
	if fix.Action != "add_lodging" || fix.CheckIn == nil || fix.CheckOut == nil {
		t.Fatalf("lodging fix = %+v", fix)
	}
	if *fix.CheckIn != "2026-08-03" || *fix.CheckOut != "2026-08-04" {
		t.Fatalf("check_in/out = %q/%q, want 2026-08-03/2026-08-04", *fix.CheckIn, *fix.CheckOut)
	}
	// check_out is exactly check_in + 1 day.
	ci, _ := time.Parse(dateLayout, *fix.CheckIn)
	co, _ := time.Parse(dateLayout, *fix.CheckOut)
	if co.Sub(ci) != 24*time.Hour {
		t.Fatalf("check_out is not check_in + 1 day: %v", co.Sub(ci))
	}
	if fix.City == nil || *fix.City != "Nice" {
		t.Fatalf("expected city Nice from the night's items, got %v", fix.City)
	}
}

func TestFix_TransitGreekFerry(t *testing.T) {
	trip := store.Trip{ID: uuid.New(),
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03")}
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Acropolis", City: strp("Athens"), Day: i32p(1)},
		{ID: uuid.New(), Name: "Portara", City: strp("Naxos"), Day: i32p(2)},
	}
	fs := checkTransit(exportData{Trip: trip, Items: items})
	if len(fs) != 1 || fs[0].Fix == nil {
		t.Fatalf("expected one transit finding with a fix, got %+v", fs)
	}
	fix := fs[0].Fix
	if fix.Action != "add_transport" || fix.Label != "Add ferry" {
		t.Fatalf("greek transit fix = %+v", fix)
	}
	if fix.Origin == nil || *fix.Origin != "Athens" || fix.Destination == nil || *fix.Destination != "Naxos" {
		t.Fatalf("origin/destination = %v/%v", fix.Origin, fix.Destination)
	}
	if fix.Mode == nil || *fix.Mode != "ferry" {
		t.Fatalf("expected ferry mode, got %v", fix.Mode)
	}
	// Destination hub's first day (Day 2 = start + 1) drives the leg date.
	if fix.Date == nil || *fix.Date != "2026-08-02" {
		t.Fatalf("transit date = %v, want 2026-08-02", fix.Date)
	}

	// Non-Greek pair → generic transport + flight, no forced ferry label.
	nonGreek := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Colosseum", City: strp("Rome"), Day: i32p(1)},
		{ID: uuid.New(), Name: "Duomo", City: strp("Florence"), Day: i32p(2)},
	}
	gf := checkTransit(exportData{Trip: trip, Items: nonGreek})
	if len(gf) != 1 || gf[0].Fix == nil || gf[0].Fix.Label != "Add transport" ||
		gf[0].Fix.Mode == nil || *gf[0].Fix.Mode != "flight" {
		t.Fatalf("non-greek transit fix = %+v", gf)
	}
}

// A trip-level travel_mode steers the missing-transport fix away from the
// flight default; Greek island legs keep ferry and 'mixed' falls through.
func TestFix_TransitRespectsTravelMode(t *testing.T) {
	items := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Whaling Museum", City: strp("Nantucket"), Day: i32p(1)},
		{ID: uuid.New(), Name: "Freedom Trail", City: strp("Boston"), Day: i32p(2)},
	}
	tripWith := func(mode *string) store.Trip {
		return store.Trip{ID: uuid.New(),
			StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03"),
			TravelMode: mode}
	}

	fs := checkTransit(exportData{Trip: tripWith(strp("car")), Items: items})
	if len(fs) != 1 || fs[0].Fix == nil || fs[0].Fix.Label != "Add drive" ||
		fs[0].Fix.Mode == nil || *fs[0].Fix.Mode != "car" {
		t.Fatalf("car-trip transit fix = %+v", fs)
	}

	// mixed is not a segment mode → keeps the flight default.
	fs = checkTransit(exportData{Trip: tripWith(strp("mixed")), Items: items})
	if len(fs) != 1 || fs[0].Fix == nil || *fs[0].Fix.Mode != "flight" {
		t.Fatalf("mixed-trip transit fix = %+v", fs)
	}

	// Greek island pair stays ferry even on a car trip.
	greek := []store.ItineraryItem{
		{ID: uuid.New(), Name: "Acropolis", City: strp("Athens"), Day: i32p(1)},
		{ID: uuid.New(), Name: "Portara", City: strp("Naxos"), Day: i32p(2)},
	}
	fs = checkTransit(exportData{Trip: tripWith(strp("car")), Items: greek})
	if len(fs) != 1 || fs[0].Fix == nil || *fs[0].Fix.Mode != "ferry" {
		t.Fatalf("greek car-trip transit fix = %+v", fs)
	}
}

func TestFix_BookingsEntityType(t *testing.T) {
	d := exportData{
		Trip: store.Trip{ID: uuid.New()},
		Accommodations: []store.Accommodation{
			{ID: uuid.New(), Name: "Hotel", Booked: false},
		},
		Segments: []store.TripSegment{
			{ID: uuid.New(), Mode: "flight", Origin: strp("JFK"), Destination: strp("CDG"), Booked: false},
		},
	}
	fs := checkBookings(d)
	if len(fs) != 2 {
		t.Fatalf("expected 2 booking findings, got %+v", fs)
	}
	byEntity := map[string]*FindingFix{}
	for _, f := range fs {
		if f.Fix == nil || f.Fix.Action != "mark_booked" || f.Fix.EntityType == nil {
			t.Fatalf("booking fix shape = %+v", f.Fix)
		}
		if f.Fix.ItemID == nil || *f.Fix.ItemID != *f.ItemID {
			t.Fatalf("booking fix item_id should mirror the finding's: %+v", f)
		}
		byEntity[*f.Fix.EntityType] = f.Fix
	}
	if byEntity["accommodation"] == nil || byEntity["segment"] == nil {
		t.Fatalf("expected one accommodation and one segment fix, got %v", byEntity)
	}
}

func TestFix_DatesBeyondSpan(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03")} // 3-day span
	id := uuid.New()
	items := []store.ItineraryItem{{ID: id, Name: "Way Out", Day: i32p(9)}}
	fs := checkDates(exportData{Trip: trip, Items: items})
	if len(fs) != 1 || fs[0].Fix == nil {
		t.Fatalf("expected one beyond-span finding with a fix, got %+v", fs)
	}
	fix := fs[0].Fix
	if fix.Action != "move_item" || fix.ItemID == nil || *fix.ItemID != id.String() {
		t.Fatalf("beyond-span fix = %+v", fix)
	}
	if fix.TargetDay == nil || *fix.TargetDay != 3 || *fix.TargetDay > 3 {
		t.Fatalf("target_day = %v, want 3 (within span)", fix.TargetDay)
	}
}

func TestFix_OverPacked_LighterDayAndNone(t *testing.T) {
	tripID := uuid.New()
	// Day 1 over-packed (7 items); Day 2 light (1 item) → the over-packed fix
	// moves the last Day-1 item to Day 2.
	var items []store.ItineraryItem
	var lastDay1 uuid.UUID
	for i := 0; i < 7; i++ {
		id := uuid.New()
		lastDay1 = id
		items = append(items, store.ItineraryItem{ID: id, Name: fmt.Sprintf("A%d", i), Day: i32p(1)})
	}
	items = append(items, store.ItineraryItem{ID: uuid.New(), Name: "B", Day: i32p(2)})
	fs := checkDensity(exportData{Trip: store.Trip{ID: tripID}, Items: items})
	var packed *Finding
	for i := range fs {
		if fs[i].Severity == "warn" && strings.Contains(fs[i].Message, "too packed") {
			packed = &fs[i]
		}
	}
	if packed == nil || packed.Fix == nil {
		t.Fatalf("expected an over-packed warn with a fix, got %+v", fs)
	}
	if packed.Fix.Action != "move_item" || packed.Fix.TargetDay == nil || *packed.Fix.TargetDay != 2 {
		t.Fatalf("over-packed fix = %+v", packed.Fix)
	}
	if packed.Fix.ItemID == nil || *packed.Fix.ItemID != lastDay1.String() {
		t.Fatalf("expected the last Day-1 item to move, got %v", packed.Fix.ItemID)
	}

	// No lighter day: Day 1 is the ONLY scheduled day (7 items) → fix stays nil.
	var solo []store.ItineraryItem
	for i := 0; i < 7; i++ {
		solo = append(solo, store.ItineraryItem{ID: uuid.New(), Name: fmt.Sprintf("C%d", i), Day: i32p(1)})
	}
	sf := checkDensity(exportData{Trip: store.Trip{ID: tripID}, Items: solo})
	for _, f := range sf {
		if strings.Contains(f.Message, "too packed") && f.Fix != nil {
			t.Fatalf("no lighter day exists — over-packed fix should be nil, got %+v", f.Fix)
		}
	}
}

func TestFix_WeatherRainAddPacking(t *testing.T) {
	start := time.Now().AddDate(0, 0, 3)
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: pgtype.Date{Time: start.Truncate(24 * time.Hour), Valid: true},
		EndDate:   pgtype.Date{Time: start.AddDate(0, 0, 1).Truncate(24 * time.Hour), Valid: true}}
	d := exportData{Trip: trip, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "Eiffel Tower", City: strp("Paris"), Category: strp("attraction"), Day: i32p(1)},
	}}
	weather := weatherStub(t, true, 22, 14)
	var gotFix bool
	for _, f := range checkWeather(context.Background(), d, weather) {
		if strings.Contains(f.Message, "umbrella") {
			if f.Fix == nil || f.Fix.Action != "add_packing" ||
				f.Fix.PackingItem == nil || *f.Fix.PackingItem != "Umbrella" {
				t.Fatalf("rain fix = %+v", f.Fix)
			}
			gotFix = true
		}
	}
	if !gotFix {
		t.Fatal("expected a rain finding carrying an add_packing fix")
	}
}

func TestReviewTrip_CleanTripNoFindings(t *testing.T) {
	// A fully-covered, transport-connected, single-city dated trip with a booked
	// stay and no over-packing → zero findings (and a JSON "[]", not null).
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-02")} // 1 night
	d := exportData{
		Trip: trip,
		Items: []store.ItineraryItem{
			{ID: uuid.New(), Name: "Louvre", City: strp("Paris"), Day: i32p(1)},
		},
		Accommodations: []store.Accommodation{{ID: uuid.New(), Name: "Hotel", Booked: true,
			CheckIn: dateVal(t, "2026-08-01"), CheckOut: dateVal(t, "2026-08-02")}},
	}
	fs := reviewTrip(context.Background(), d, reviewOptions{}, reviewDeps{})
	if len(fs) != 0 {
		t.Fatalf("clean trip should have no findings, got %+v", fs)
	}
	if b, _ := json.Marshal(fs); string(b) != "[]" {
		t.Fatalf("expected JSON [], got %s", b)
	}
}

func TestReviewTrip_DeterministicOrder(t *testing.T) {
	trip := store.Trip{ID: uuid.New(), Status: "planned",
		StartDate: dateVal(t, "2026-08-01"), EndDate: dateVal(t, "2026-08-03")}
	d := exportData{Trip: trip, Items: []store.ItineraryItem{
		{ID: uuid.New(), Name: "A"}, // unscheduled
	}}
	ja, _ := json.Marshal(reviewTrip(context.Background(), d, reviewOptions{}, reviewDeps{}))
	jb, _ := json.Marshal(reviewTrip(context.Background(), d, reviewOptions{}, reviewDeps{}))
	if string(ja) != string(jb) {
		t.Fatalf("nondeterministic order:\n%s\n%s", ja, jb)
	}
}
