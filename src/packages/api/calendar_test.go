package main

// calendar_test.go — pure unit tests for the .ics builders (no DB):
// time-of-day windows, description assembly, timed-vs-all-day formatting, and
// RFC 5545 line folding. See specs/calendar-export-timed-events.

import (
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"travel-route-planner/store"
)

// unfoldICS reverses RFC 5545 folding so a test can assert on logical lines.
func unfoldICS(s string) string { return strings.ReplaceAll(s, "\r\n ", "") }

func TestItemTimeWindow(t *testing.T) {
	day := time.Date(2026, 8, 3, 0, 0, 0, 0, time.UTC)

	cases := []struct {
		timeOfDay          string
		wantOK             bool
		startHour, endHour int
	}{
		{"morning", true, 9, 12},
		{"afternoon", true, 13, 17},
		{"evening", true, 19, 22},
		{"  Morning  ", true, 9, 12}, // normalized like the rest of the codebase
		{"", false, 0, 0},
		{"night", false, 0, 0}, // not in the server-validated enum
	}
	for _, c := range cases {
		start, end, ok := itemTimeWindow(day, c.timeOfDay)
		if ok != c.wantOK {
			t.Fatalf("%q: ok = %v, want %v", c.timeOfDay, ok, c.wantOK)
		}
		if !ok {
			if !start.IsZero() || !end.IsZero() {
				t.Fatalf("%q: expected zero times when ok=false", c.timeOfDay)
			}
			continue
		}
		if start.Hour() != c.startHour || end.Hour() != c.endHour {
			t.Fatalf("%q: got %d–%d, want %d–%d", c.timeOfDay, start.Hour(), end.Hour(), c.startHour, c.endHour)
		}
		if start.Year() != 2026 || start.Month() != time.August || start.Day() != 3 {
			t.Fatalf("%q: window moved off the item's day: %v", c.timeOfDay, start)
		}
	}
}

func TestICSStayDescription(t *testing.T) {
	full := store.Accommodation{
		Provider:  strp("Booking.com"),
		PriceNote: strp("€180/night"),
		Url:       strp("https://www.booking.com/hotel/gr/grande.html?aid=42"),
		Booked:    true,
	}
	if got, want := icsStayDescription("en", full),
		"Booking.com · €180/night · Booked · booking.com/hotel/gr/grande.html"; got != want {
		t.Fatalf("full stay description = %q, want %q", got, want)
	}

	// Unbooked drops the label rather than saying "Not booked".
	unbooked := full
	unbooked.Booked = false
	if got := icsStayDescription("en", unbooked); strings.Contains(got, "Booked") {
		t.Fatalf("unbooked stay should omit the flag, got %q", got)
	}

	// Missing fields must not leave dangling separators.
	sparse := store.Accommodation{PriceNote: strp("€180/night")}
	if got, want := icsStayDescription("en", sparse), "€180/night"; got != want {
		t.Fatalf("sparse stay description = %q, want %q", got, want)
	}
	if got := icsStayDescription("en", store.Accommodation{}); got != "" {
		t.Fatalf("empty stay description = %q, want empty", got)
	}

	if got := icsStayDescription("es", full); !strings.Contains(got, "Reservado") {
		t.Fatalf("es stay description should localize the booked flag, got %q", got)
	}
}

func TestICSSegmentDescription(t *testing.T) {
	full := store.TripSegment{
		Provider:  strp("Delta"),
		PriceNote: strp("$780"),
		Notes:     strp("Departs 6:30 PM"),
		Url:       strp("https://www.delta.com/booking/xyz"),
		Booked:    true,
	}
	if got, want := icsSegmentDescription("en", full),
		"Delta · $780 · Booked · Departs 6:30 PM · delta.com/booking/xyz"; got != want {
		t.Fatalf("full segment description = %q, want %q", got, want)
	}
	// Notes alone is the pre-existing behavior and must survive.
	if got, want := icsSegmentDescription("en", store.TripSegment{Notes: strp("Seat 14A")}), "Seat 14A"; got != want {
		t.Fatalf("notes-only description = %q, want %q", got, want)
	}
	if got := icsSegmentDescription("en", store.TripSegment{}); got != "" {
		t.Fatalf("empty segment description = %q, want empty", got)
	}
}

func TestICSBuilderEventTimedVsAllDay(t *testing.T) {
	var timed icsBuilder
	timed.event("20260101T000000Z", icsEvent{
		UID:     "item-x",
		Start:   time.Date(2026, 8, 3, 9, 0, 0, 0, time.UTC),
		End:     time.Date(2026, 8, 3, 12, 0, 0, 0, time.UTC),
		Summary: "Acropolis",
	})
	got := timed.String()
	if !strings.Contains(got, "DTSTART:20260803T090000\r\n") || !strings.Contains(got, "DTEND:20260803T120000\r\n") {
		t.Fatalf("timed DTSTART/DTEND wrong:\n%s", got)
	}
	// Floating: the DT lines carry no Z and no TZID (DTSTAMP is legitimately
	// UTC and keeps its Z).
	if strings.Contains(got, "DTSTART:20260803T090000Z") || strings.Contains(got, "DTEND:20260803T120000Z") ||
		strings.Contains(got, "TZID=") || strings.Contains(got, "VALUE=DATE") {
		t.Fatalf("timed event must be floating and not a DATE value:\n%s", got)
	}

	var allDay icsBuilder
	allDay.event("20260101T000000Z", icsEvent{
		UID:     "acc-x",
		Start:   time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC),
		End:     time.Date(2026, 8, 5, 0, 0, 0, 0, time.UTC),
		AllDay:  true,
		Summary: "Stay: Hotel",
	})
	if got := allDay.String(); !strings.Contains(got, "DTSTART;VALUE=DATE:20260801") ||
		!strings.Contains(got, "DTEND;VALUE=DATE:20260805") {
		t.Fatalf("all-day DTSTART/DTEND wrong:\n%s", got)
	}
}

func TestICSBuilderURLIsNotTextEscaped(t *testing.T) {
	raw := "https://example.com/book?a=1,2;b=3"
	var b icsBuilder
	b.event("20260101T000000Z", icsEvent{
		UID: "seg-x", AllDay: true,
		Start: time.Now(), End: time.Now(),
		Summary:     "Flight",
		Description: raw, // same string as TEXT — must be escaped here
		URL:         raw, // …but verbatim as a URI value
	})
	got := unfoldICS(b.String())
	if !strings.Contains(got, "URL:"+raw) {
		t.Fatalf("URL should be verbatim (URI value type):\n%s", got)
	}
	if !strings.Contains(got, `DESCRIPTION:https://example.com/book?a=1\,2\;b=3`) {
		t.Fatalf("DESCRIPTION should be TEXT-escaped:\n%s", got)
	}
}

// TestFoldICSLine covers RFC 5545 §3.1 folding, which enriched descriptions now
// routinely trigger — before this feature every value was short enough that
// folding never ran in practice.
func TestFoldICSLine(t *testing.T) {
	assertFolded := func(t *testing.T, in string) {
		t.Helper()
		out := foldICSLine(in)
		for i, seg := range strings.Split(out, "\r\n") {
			if i > 0 && !strings.HasPrefix(seg, " ") {
				t.Fatalf("continuation %d must start with one space: %q", i, seg)
			}
			if len(seg) > 75 {
				t.Fatalf("segment %d is %d octets (>75): %q", i, len(seg), seg)
			}
			if !utf8.ValidString(seg) {
				t.Fatalf("segment %d split a rune: %q", i, seg)
			}
		}
		if got := unfoldICS(out); got != in {
			t.Fatalf("unfold round-trip failed:\ngot  %q\nwant %q", got, in)
		}
	}

	short := "SUMMARY:Acropolis"
	if got := foldICSLine(short); got != short {
		t.Fatalf("short line should pass through, got %q", got)
	}
	assertFolded(t, "DESCRIPTION:"+strings.Repeat("a", 300))
	// Multi-byte: 2-byte runes, and a 4-byte rune placed to straddle the
	// 75-octet boundary.
	assertFolded(t, "DESCRIPTION:"+strings.Repeat("é", 60))
	assertFolded(t, "DESCRIPTION:"+strings.Repeat("a", 72)+"𝄞"+strings.Repeat("b", 40))
}

// TestBuildICSDocument pins a whole document (DTSTAMP included, via the icsNow
// seam) so the calendar's overall shape is covered, not just its fragments.
func TestBuildICSDocument(t *testing.T) {
	prev := icsNow
	icsNow = func() time.Time { return time.Date(2026, 7, 20, 12, 0, 0, 0, time.UTC) }
	t.Cleanup(func() { icsNow = prev })

	day := int32(1)
	tod := "evening"
	d := exportData{
		Trip: store.Trip{
			ID:        uuid.New(),
			Title:     "Greek Islands",
			StartDate: pgDate(t, "2026-08-01"),
			EndDate:   pgDate(t, "2026-08-05"),
		},
		Items: []store.ItineraryItem{{
			ID: uuid.New(), Name: "Sunset dinner", Day: &day, TimeOfDay: &tod,
		}},
	}
	body := buildICS("en", d)

	for _, want := range []string{
		"BEGIN:VCALENDAR\r\n",
		"X-WR-CALNAME:Greek Islands\r\n",
		"DTSTAMP:20260720T120000Z\r\n",
		"DTSTART:20260801T190000\r\n", // evening window on day 1
		"DTEND:20260801T220000\r\n",
		"END:VCALENDAR\r\n",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("missing %q in:\n%s", want, body)
		}
	}
	// One real event ⇒ no trip-span fallback event.
	if n := strings.Count(body, "BEGIN:VEVENT"); n != 1 {
		t.Fatalf("expected 1 VEVENT, got %d:\n%s", n, body)
	}
}

func TestBuildICSEmptyTripStillYieldsSpanEvent(t *testing.T) {
	d := exportData{Trip: store.Trip{
		ID: uuid.New(), Title: "Empty", StartDate: pgDate(t, "2026-08-01"), EndDate: pgDate(t, "2026-08-03"),
	}}
	body := buildICS("en", d)
	if n := strings.Count(body, "BEGIN:VEVENT"); n != 1 {
		t.Fatalf("expected the trip-span fallback event, got %d:\n%s", n, body)
	}
	if !strings.Contains(body, "DTSTART;VALUE=DATE:20260801") ||
		!strings.Contains(body, "DTEND;VALUE=DATE:20260804") {
		t.Fatalf("trip-span event dates wrong:\n%s", body)
	}
}
