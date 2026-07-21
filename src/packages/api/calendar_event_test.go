package main

import (
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// Unit tests for buildSingleEventICS — pure, no DB: the export snapshot is
// constructed as literals.

func singleEventFixture(t *testing.T) exportData {
	t.Helper()
	day := int32(3)
	tod := "morning"
	rec := "Maria"
	return exportData{
		Trip: store.Trip{
			ID:        uuid.New(),
			Title:     "Greek Islands",
			StartDate: pgDate(t, "2026-08-01"),
		},
		Items: []store.ItineraryItem{{
			ID:              uuid.New(),
			Name:            "Acropolis, ruins",
			Address:         strp("Athens 105 58"),
			Day:             &day,
			TimeOfDay:       &tod,
			LocalSourceName: &rec,
		}},
		Accommodations: []store.Accommodation{{
			ID:       uuid.New(),
			Name:     "Hotel Grande Bretagne",
			Address:  strp("Syntagma Square"),
			CheckIn:  pgDate(t, "2026-08-01"),
			CheckOut: pgDate(t, "2026-08-05"),
		}},
		Segments: []store.TripSegment{{
			ID:          uuid.New(),
			Mode:        "flight",
			Origin:      strp("JFK"),
			Destination: strp("ATH"),
			DepartDate:  pgDate(t, "2026-08-01"),
			ArriveDate:  pgDate(t, "2026-08-02"),
		}},
	}
}

func TestBuildSingleEventICS_Stay(t *testing.T) {
	d := singleEventFixture(t)
	body, filename, ok := buildSingleEventICS("en", d, "stay", d.Accommodations[0].ID)
	if !ok {
		t.Fatal("stay should render")
	}
	if filename != "stay-hotel-grande-bretagne" {
		t.Fatalf("filename: %q", filename)
	}
	if n := strings.Count(body, "BEGIN:VEVENT"); n != 1 {
		t.Fatalf("expected exactly 1 VEVENT, got %d\n%s", n, body)
	}
	for _, want := range []string{
		"BEGIN:VCALENDAR",
		"UID:acc-" + d.Accommodations[0].ID.String() + "@goldentempo",
		"DTSTART;VALUE=DATE:20260801",
		"DTEND;VALUE=DATE:20260805", // check-out day, end-exclusive
		"SUMMARY:Stay: Hotel Grande Bretagne",
		"LOCATION:Syntagma Square",
		"END:VCALENDAR",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in:\n%s", want, body)
		}
	}
}

func TestBuildSingleEventICS_StayWithoutCheckoutIsOneNight(t *testing.T) {
	d := singleEventFixture(t)
	d.Accommodations[0].CheckOut = pgtype.Date{}
	body, _, ok := buildSingleEventICS("en", d, "stay", d.Accommodations[0].ID)
	if !ok {
		t.Fatal("stay without checkout should still render")
	}
	if !strings.Contains(body, "DTEND;VALUE=DATE:20260802") {
		t.Fatalf("expected one-night DTEND 20260802 in:\n%s", body)
	}
}

func TestBuildSingleEventICS_Segment(t *testing.T) {
	d := singleEventFixture(t)
	body, filename, ok := buildSingleEventICS("en", d, "segment", d.Segments[0].ID)
	if !ok {
		t.Fatal("segment should render")
	}
	if filename != "flight-jfk-ath" {
		t.Fatalf("filename: %q", filename)
	}
	for _, want := range []string{
		"UID:seg-" + d.Segments[0].ID.String() + "@goldentempo",
		"SUMMARY:Flight: JFK → ATH",
		"DTSTART;VALUE=DATE:20260801",
		"DTEND;VALUE=DATE:20260803", // arrival day + 1, end-exclusive
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in:\n%s", want, body)
		}
	}
}

func TestBuildSingleEventICS_SegmentSameDayArrival(t *testing.T) {
	d := singleEventFixture(t)
	d.Segments[0].ArriveDate = d.Segments[0].DepartDate
	body, _, ok := buildSingleEventICS("en", d, "segment", d.Segments[0].ID)
	if !ok {
		t.Fatal("same-day segment should render")
	}
	if !strings.Contains(body, "DTEND;VALUE=DATE:20260802") {
		t.Fatalf("expected single-day DTEND 20260802 in:\n%s", body)
	}
}

func TestBuildSingleEventICS_Item(t *testing.T) {
	d := singleEventFixture(t)
	body, _, ok := buildSingleEventICS("en", d, "item", d.Items[0].ID)
	if !ok {
		t.Fatal("item should render")
	}
	for _, want := range []string{
		"UID:item-" + d.Items[0].ID.String() + "@goldentempo",
		// Timed: trip start + (day 3 − 1), morning window 09:00–12:00.
		"DTSTART:20260803T090000",
		"DTEND:20260803T120000",
		`SUMMARY:Acropolis\, ruins`, // RFC 5545 comma escaping
		"DESCRIPTION:Morning · Recommended by Maria",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in:\n%s", want, body)
		}
	}
	// Timed items must be FLOATING: a Z suffix or a TZID would pin them to one
	// zone and shift the event when the traveler lands.
	if strings.Contains(body, "20260803T090000Z") || strings.Contains(body, "TZID=") {
		t.Fatalf("item time must be floating, got:\n%s", body)
	}
	if strings.Contains(body, "VALUE=DATE") {
		t.Fatalf("timed item must not emit a DATE value:\n%s", body)
	}
}

func TestBuildSingleEventICS_ItemWithoutTimeOfDayIsAllDay(t *testing.T) {
	d := singleEventFixture(t)
	d.Items[0].TimeOfDay = nil
	body, _, ok := buildSingleEventICS("en", d, "item", d.Items[0].ID)
	if !ok {
		t.Fatal("item without time_of_day should still render")
	}
	for _, want := range []string{
		"DTSTART;VALUE=DATE:20260803",
		"DTEND;VALUE=DATE:20260804",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in:\n%s", want, body)
		}
	}
}

func TestBuildSingleEventICS_StayCarriesBookingDetails(t *testing.T) {
	d := singleEventFixture(t)
	a := &d.Accommodations[0]
	a.Provider = strp("Booking.com")
	a.PriceNote = strp("€180/night")
	a.Url = strp("https://www.booking.com/hotel/gr/grande.html?aid=42,7")
	a.Booked = true

	body, _, ok := buildSingleEventICS("en", d, "stay", a.ID)
	if !ok {
		t.Fatal("stay should render")
	}
	// Description carries the readable link; the raw href rides URL. Unfold
	// first — these values are long enough to trigger RFC 5545 folding.
	if want := "DESCRIPTION:Booking.com · €180/night · Booked · booking.com/hotel/gr/grande.html"; !strings.Contains(unfoldICS(body), want) {
		t.Fatalf("missing %q in:\n%s", want, body)
	}
	// URL is a URI value: the comma in the query string must NOT be escaped,
	// while the same comma inside DESCRIPTION text would be.
	if want := "URL:https://www.booking.com/hotel/gr/grande.html?aid=42,7"; !strings.Contains(unfoldICS(body), want) {
		t.Fatalf("missing unescaped %q in:\n%s", want, body)
	}
}

func TestBuildSingleEventICS_SegmentCarriesBookingDetails(t *testing.T) {
	d := singleEventFixture(t)
	s := &d.Segments[0]
	s.Provider = strp("Delta")
	s.PriceNote = strp("$780")
	s.Notes = strp("Departs 6:30 PM")
	s.Url = strp("https://www.delta.com/booking/xyz")
	s.Booked = true

	body, _, ok := buildSingleEventICS("en", d, "segment", s.ID)
	if !ok {
		t.Fatal("segment should render")
	}
	if want := "DESCRIPTION:Delta · $780 · Booked · Departs 6:30 PM · delta.com/booking/xyz"; !strings.Contains(unfoldICS(body), want) {
		t.Fatalf("missing %q in:\n%s", want, body)
	}
}

func TestBuildSingleEventICS_NoBookingDetailsOmitsLines(t *testing.T) {
	// The bare fixture has no provider/price/url and is unbooked: no
	// DESCRIPTION and no URL line at all, rather than empty ones.
	d := singleEventFixture(t)
	body, _, ok := buildSingleEventICS("en", d, "stay", d.Accommodations[0].ID)
	if !ok {
		t.Fatal("stay should render")
	}
	if strings.Contains(body, "DESCRIPTION:") || strings.Contains(body, "URL:") {
		t.Fatalf("bare stay should emit neither DESCRIPTION nor URL:\n%s", body)
	}
}

func TestBuildSingleEventICS_NotFoundCases(t *testing.T) {
	d := singleEventFixture(t)

	undatedStay := singleEventFixture(t)
	undatedStay.Accommodations[0].CheckIn = pgtype.Date{}

	undatedSegment := singleEventFixture(t)
	undatedSegment.Segments[0].DepartDate = pgtype.Date{}

	daylessItem := singleEventFixture(t)
	daylessItem.Items[0].Day = nil

	startlessTrip := singleEventFixture(t)
	startlessTrip.Trip.StartDate = pgtype.Date{}

	cases := []struct {
		name string
		d    exportData
		kind string
		id   uuid.UUID
	}{
		{"unknown kind", d, "hovercraft", d.Accommodations[0].ID},
		{"unknown id", d, "stay", uuid.New()},
		{"wrong-kind id", d, "segment", d.Accommodations[0].ID},
		{"undated stay", undatedStay, "stay", undatedStay.Accommodations[0].ID},
		{"undated segment", undatedSegment, "segment", undatedSegment.Segments[0].ID},
		{"dayless item", daylessItem, "item", daylessItem.Items[0].ID},
		{"trip without start date", startlessTrip, "item", startlessTrip.Items[0].ID},
	}
	for _, tc := range cases {
		if _, _, ok := buildSingleEventICS("en", tc.d, tc.kind, tc.id); ok {
			t.Fatalf("%s: expected ok=false", tc.name)
		}
	}
}

// Calendar titles are a cross-language contract: the Flutter client builds
// Google Calendar links for the SAME events, so the two must agree in every
// locale. These expectations are mirrored in the Flutter suite
// (flutter-app/test/calendar_title_parity_test.dart) — a drift on either side
// fails a test instead of shipping two differently-named entries for one trip.
func TestSingleEventICSSpanishTitles(t *testing.T) {
	d := singleEventFixture(t)

	body, _, ok := buildSingleEventICS("es", d, "stay", d.Accommodations[0].ID)
	if !ok {
		t.Fatal("stay should render")
	}
	if want := "SUMMARY:Alojamiento: Hotel Grande Bretagne"; !strings.Contains(body, want) {
		t.Errorf("es stay summary missing %q\n%s", want, body)
	}

	body, _, ok = buildSingleEventICS("es", d, "segment", d.Segments[0].ID)
	if !ok {
		t.Fatal("segment should render")
	}
	// The route itself is traveler data and stays as-is; only the mode word
	// translates.
	if want := "SUMMARY:Vuelo: JFK → ATH"; !strings.Contains(body, want) {
		t.Errorf("es segment summary missing %q\n%s", want, body)
	}
}
