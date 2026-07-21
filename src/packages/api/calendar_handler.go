package main

import (
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// calendar_handler.go — GET /api/v1/export/{token}/calendar.ics, the trip as an
// RFC 5545 iCalendar file. Token-gated and PUBLIC (the signed token is the
// capability). Stays and transport are all-day VEVENTs (the data model has no
// clock times for them); itinerary items become timed events derived from their
// time_of_day bucket (specs/calendar-export-timed-events). Zero external deps —
// the string is built by hand with careful TEXT escaping and line folding.

const (
	icsDateLayout = "20060102"
	// icsDateTimeLayout is a FLOATING local date-time: no trailing Z and no
	// TZID, so the event renders at the same wall clock in whatever timezone
	// the traveler's device is in. That is the right semantic for a trip — 9am
	// in Athens should stay 9am when you land.
	icsDateTimeLayout = "20060102T150405"
)

// icsEvent is one resolved VEVENT, shared by the whole-trip calendar and the
// per-event endpoint (calendar_event_handler.go) so both render identically.
type icsEvent struct {
	// UID is the pre-suffix identity ("item-<uuid>"); the builder appends
	// "@goldentempo". The scheme is byte-stable BY CONTRACT: adding a single
	// event after a whole-trip import dedupes on it. Never change a prefix.
	UID string

	// Start/End are exclusive-end. All-day events format as DATE values;
	// timed events as floating DATE-TIMEs (see icsDateTimeLayout).
	Start, End time.Time
	AllDay     bool

	Summary     string
	Location    string
	Description string
	URL         string
}

// calendarHandler streams the trip's .ics attachment.
func calendarHandler(w http.ResponseWriter, r *http.Request) {
	data, ok := resolveExport(r, mux.Vars(r)["token"])
	if !ok {
		// Match the print route: opaque 404, no leak.
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("export link not available"))
		return
	}
	// localeMiddleware has already resolved ?lang= / Accept-Language. Calendar
	// apps fetch this URL themselves, so an explicit ?lang= on the share link is
	// the reliable signal; the header is the fallback.
	body := buildICS(requestLocale(r.Context()), data)
	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="`+tripSlug(data.Trip.Title)+`.ics"`)
	w.Write([]byte(body))
}

// buildICS renders the export data as a VCALENDAR document. Undatable itinerary
// items are skipped; if nothing at all is datable the calendar still contains a
// single trip-span all-day event so the download is never empty.
func buildICS(locale string, d exportData) string {
	var b icsBuilder
	b.line("BEGIN:VCALENDAR")
	b.line("VERSION:2.0")
	b.line("PRODID:-//Golden Tempo Travel//Trip Export//EN")
	b.line("CALSCALE:GREGORIAN")
	b.line("METHOD:PUBLISH")

	// X-WR-CALNAME labels the import in Google/Apple Calendar ("Greek Islands"
	// instead of an unnamed pile of events). Non-standard but widely honored.
	// Deliberately NOT set on the single-event file (some clients offer to
	// create a whole calendar named after that one event), and X-WR-TIMEZONE is
	// deliberately absent — it would pin the floating item times to one zone.
	if name := strings.TrimSpace(d.Trip.Title); name != "" {
		b.line("X-WR-CALNAME:" + escapeICSText(name))
	}

	stamp := icsNow().UTC().Format("20060102T150405Z")
	events := 0

	for _, it := range d.Items {
		if ev, ok := itemEventFieldsIn(locale, d.Trip, it); ok {
			b.event(stamp, ev) // no trip start_date or no day → not datable
			events++
		}
	}

	for _, a := range d.Accommodations {
		if ev, ok := stayEventFieldsIn(locale, a); ok {
			b.event(stamp, ev)
			events++
		}
	}

	for _, s := range d.Segments {
		if ev, ok := segmentEventFieldsIn(locale, s); ok {
			b.event(stamp, ev)
			events++
		}
	}

	// Fallback: a datable-but-empty export still yields one trip-span event.
	if events == 0 && d.Trip.StartDate.Valid {
		end := d.Trip.StartDate.Time.AddDate(0, 0, 1)
		if d.Trip.EndDate.Valid && d.Trip.EndDate.Time.After(d.Trip.StartDate.Time) {
			end = d.Trip.EndDate.Time.AddDate(0, 0, 1)
		}
		b.event(stamp, icsEvent{
			UID:     "trip-" + d.Trip.ID.String(),
			Start:   d.Trip.StartDate.Time,
			End:     end,
			AllDay:  true,
			Summary: d.Trip.Title,
		})
	}

	b.line("END:VCALENDAR")
	return b.String()
}

// The three per-kind field resolvers below are shared by the whole-trip
// calendar and the single-event endpoint (calendar_event_handler.go) so both
// render identical VEVENTs. All ends are exclusive; ok=false means the event is
// undated and gets no VEVENT.

// stayEventFieldsIn resolves an accommodation's VEVENT: check-in through
// check-out (or one night when check-out is missing/not after check-in),
// all-day. The SUMMARY is mirrored byte-for-byte by the Flutter client's Google
// Calendar link (bookings_section.dart) — change both together.
func stayEventFieldsIn(locale string, a store.Accommodation) (icsEvent, bool) {
	if !a.CheckIn.Valid {
		return icsEvent{}, false
	}
	end := a.CheckIn.Time.AddDate(0, 0, 1)
	if a.CheckOut.Valid && a.CheckOut.Time.After(a.CheckIn.Time) {
		end = a.CheckOut.Time
	}
	return icsEvent{
		UID:         "acc-" + a.ID.String(),
		Start:       a.CheckIn.Time,
		End:         end,
		AllDay:      true,
		Summary:     tr(locale, "ics.stayTitle", a.Name),
		Location:    strPtrVal(a.Address),
		Description: icsStayDescription(locale, a),
		URL:         strings.TrimSpace(strPtrVal(a.Url)),
	}, true
}

// segmentEventFieldsIn resolves a transport segment's VEVENT: departure day
// through arrival day inclusive (single day when arrival is missing), all-day —
// the model carries dates only, no clock times. The SUMMARY is mirrored by the
// Flutter client — see stayEventFieldsIn.
func segmentEventFieldsIn(locale string, s store.TripSegment) (icsEvent, bool) {
	if !s.DepartDate.Valid {
		return icsEvent{}, false
	}
	end := s.DepartDate.Time.AddDate(0, 0, 1)
	if s.ArriveDate.Valid && s.ArriveDate.Time.After(s.DepartDate.Time) {
		end = s.ArriveDate.Time.AddDate(0, 0, 1)
	}
	return icsEvent{
		UID:         "seg-" + s.ID.String(),
		Start:       s.DepartDate.Time,
		End:         end,
		AllDay:      true,
		Summary:     tr(locale, "ics.segmentTitle", localizedMode(locale, s.Mode), segmentRouteIn(locale, s)),
		Description: icsSegmentDescription(locale, s),
		URL:         strings.TrimSpace(strPtrVal(s.Url)),
	}, true
}

// itemEventFieldsIn resolves an itinerary item's VEVENT on the single trip day
// it is assigned to: a timed event when time_of_day gives a window, otherwise
// all-day. The SUMMARY is the item's own name — traveler data, never translated.
func itemEventFieldsIn(locale string, trip store.Trip, it store.ItineraryItem) (icsEvent, bool) {
	day, ok := itemStartDate(trip, it)
	if !ok {
		return icsEvent{}, false
	}
	ev := icsEvent{
		UID:         "item-" + it.ID.String(),
		Summary:     it.Name,
		Location:    strPtrVal(it.Address),
		Description: icsItemDescription(locale, it),
	}
	if start, end, timed := itemTimeWindow(day, strPtrVal(it.TimeOfDay)); timed {
		ev.Start, ev.End, ev.AllDay = start, end, false
	} else {
		ev.Start, ev.End, ev.AllDay = day, day.AddDate(0, 0, 1), true
	}
	return ev, true
}

// itemTimeWindow maps a time_of_day bucket onto clock times on the item's day:
// morning 09:00–12:00, afternoon 13:00–17:00, evening 19:00–22:00. ok=false for
// an empty or unrecognized bucket, which keeps the item all-day.
//
// These windows are a product-level GUESS, not traveler data — the model stores
// only the bucket. Real start_time/end_time columns are the eventual upgrade;
// mirrored in Dart by _itemTimeWindow (calendar_links.dart), change both
// together. The returned times use time.UTC purely as a container: they are
// formatted with icsDateTimeLayout, which emits no zone, so they are floating.
// Building them from day.Date() components (never Add) keeps DST out of it.
func itemTimeWindow(day time.Time, timeOfDay string) (start, end time.Time, ok bool) {
	var startHour, endHour int
	switch strings.ToLower(strings.TrimSpace(timeOfDay)) {
	case "morning":
		startHour, endHour = 9, 12
	case "afternoon":
		startHour, endHour = 13, 17
	case "evening":
		startHour, endHour = 19, 22
	default:
		return time.Time{}, time.Time{}, false
	}
	y, m, d := day.Date()
	return time.Date(y, m, d, startHour, 0, 0, 0, time.UTC),
		time.Date(y, m, d, endHour, 0, 0, 0, time.UTC), true
}

// icsStayDescription mirrors the print packet's stay meta line (toPrintStay):
// provider, price note, booked flag, and the readable form of the booking link
// — the raw href rides the URL property instead.
func icsStayDescription(locale string, a store.Accommodation) string {
	parts := icsDetailParts(
		strPtrVal(a.Provider),
		strPtrVal(a.PriceNote),
		icsBookedLabel(locale, a.Booked),
		displayURL(strPtrVal(a.Url)),
	)
	return strings.Join(parts, " · ")
}

// icsSegmentDescription mirrors toPrintSegment: provider, price note, booked
// flag, the traveler's own notes, then the readable link.
func icsSegmentDescription(locale string, s store.TripSegment) string {
	parts := icsDetailParts(
		strPtrVal(s.Provider),
		strPtrVal(s.PriceNote),
		icsBookedLabel(locale, s.Booked),
		strPtrVal(s.Notes),
		displayURL(strPtrVal(s.Url)),
	)
	return strings.Join(parts, " · ")
}

// icsDetailParts trims and drops empties so a missing field never leaves a
// dangling " ·  · " in the description.
func icsDetailParts(vals ...string) []string {
	parts := make([]string, 0, len(vals))
	for _, v := range vals {
		if v = strings.TrimSpace(v); v != "" {
			parts = append(parts, v)
		}
	}
	return parts
}

func icsBookedLabel(locale string, booked bool) string {
	if !booked {
		return ""
	}
	return tr(locale, "ics.booked")
}

// itemStartDate resolves an item's all-day start: trip.start_date + (day-1).
// Not datable when the trip has no start date or the item has no day.
func itemStartDate(trip store.Trip, it store.ItineraryItem) (time.Time, bool) {
	if !trip.StartDate.Valid || it.Day == nil || *it.Day < 1 {
		return time.Time{}, false
	}
	return trip.StartDate.Time.AddDate(0, 0, int(*it.Day)-1), true
}

// icsItemDescription joins the time-of-day and local attribution into the
// VEVENT DESCRIPTION (pre-escape; the builder escapes it).
func icsItemDescription(locale string, it store.ItineraryItem) string {
	var parts []string
	if t := localizedTimeOfDay(locale, strPtrVal(it.TimeOfDay)); t != "" {
		parts = append(parts, t)
	}
	if rec := strings.TrimSpace(strPtrVal(it.LocalSourceName)); rec != "" {
		parts = append(parts, tr(locale, "ics.recommendedBy", rec))
	}
	return strings.Join(parts, " · ")
}

// icsNow is the DTSTAMP clock, swappable so tests can pin a whole document.
var icsNow = time.Now

// icsBuilder accumulates CRLF-terminated, RFC-folded content lines.
type icsBuilder struct {
	sb strings.Builder
}

func (b *icsBuilder) line(s string) {
	b.sb.WriteString(foldICSLine(s))
	b.sb.WriteString("\r\n")
}

// event writes one VEVENT — a DATE pair when ev.AllDay, otherwise a floating
// DATE-TIME pair. Text properties are escaped here; ev's fields are raw.
func (b *icsBuilder) event(stamp string, ev icsEvent) {
	b.line("BEGIN:VEVENT")
	b.line("UID:" + ev.UID + "@goldentempo")
	b.line("DTSTAMP:" + stamp)
	if ev.AllDay {
		b.line("DTSTART;VALUE=DATE:" + ev.Start.Format(icsDateLayout))
		b.line("DTEND;VALUE=DATE:" + ev.End.Format(icsDateLayout))
	} else {
		b.line("DTSTART:" + ev.Start.Format(icsDateTimeLayout))
		b.line("DTEND:" + ev.End.Format(icsDateTimeLayout))
	}
	b.line("SUMMARY:" + escapeICSText(ev.Summary))
	if strings.TrimSpace(ev.Location) != "" {
		b.line("LOCATION:" + escapeICSText(ev.Location))
	}
	if strings.TrimSpace(ev.Description) != "" {
		b.line("DESCRIPTION:" + escapeICSText(ev.Description))
	}
	if u := strings.TrimSpace(ev.URL); u != "" {
		// URL is typed URI, not TEXT (RFC 5545 §3.8.4.6) — escaping it would
		// corrupt commas and semicolons inside query strings. Folding still
		// applies via line().
		b.line("URL:" + u)
	}
	b.line("END:VEVENT")
}

func (b *icsBuilder) String() string { return b.sb.String() }

// escapeICSText escapes a TEXT value per RFC 5545 §3.3.11: backslash, semicolon,
// and comma are backslash-escaped, and newlines become the literal "\n".
func escapeICSText(s string) string {
	r := strings.NewReplacer(
		`\`, `\\`,
		`;`, `\;`,
		`,`, `\,`,
		"\r\n", `\n`,
		"\n", `\n`,
		"\r", `\n`,
	)
	return r.Replace(s)
}

// foldICSLine folds a content line to <=75 octets per RFC 5545 §3.1, using a
// CRLF followed by a single space for each continuation. Folds on octet
// boundaries but never mid-UTF-8-rune.
func foldICSLine(s string) string {
	const limit = 75
	if len(s) <= limit {
		return s
	}
	var out strings.Builder
	line := 0
	for i := 0; i < len(s); {
		// Advance one rune so we never split a multi-byte sequence.
		size := 1
		for i+size < len(s) && s[i+size]&0xC0 == 0x80 {
			size++
		}
		if line+size > limit {
			out.WriteString("\r\n ")
			line = 1 // the leading space counts toward the folded line
		}
		out.WriteString(s[i : i+size])
		line += size
		i += size
	}
	return out.String()
}

// tripSlug turns a trip title into a filesystem-friendly slug for the .ics
// filename, falling back to "trip".
func tripSlug(title string) string {
	var b strings.Builder
	prevDash := false
	for _, r := range strings.ToLower(strings.TrimSpace(title)) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			prevDash = false
		default:
			if !prevDash {
				b.WriteByte('-')
				prevDash = true
			}
		}
	}
	slug := strings.Trim(b.String(), "-")
	if slug == "" {
		return "trip"
	}
	if len(slug) > 60 {
		slug = strings.Trim(slug[:60], "-")
	}
	return slug
}
