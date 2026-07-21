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
		"DTSTART;VALUE=DATE:20260803", // trip start + (day 3 − 1)
		"DTEND;VALUE=DATE:20260804",
		`SUMMARY:Acropolis\, ruins`, // RFC 5545 comma escaping
		"DESCRIPTION:Morning · Recommended by Maria",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in:\n%s", want, body)
		}
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
