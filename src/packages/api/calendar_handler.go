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
// capability). Everything is an all-day VEVENT so it drops cleanly onto a
// calendar's day grid. Zero external deps — the string is built by hand with
// careful TEXT escaping and line folding.

const icsDateLayout = "20060102"

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

	stamp := time.Now().UTC().Format("20060102T150405Z")
	events := 0

	for _, it := range d.Items {
		start, end, summary, location, description, ok := itemEventFieldsIn(locale, d.Trip, it)
		if !ok {
			continue // no trip start_date or no day → not datable
		}
		b.event(stamp, "item-"+it.ID.String(), start, end, summary, location, description)
		events++
	}

	for _, a := range d.Accommodations {
		start, end, summary, location, ok := stayEventFieldsIn(locale, a)
		if !ok {
			continue
		}
		b.event(stamp, "acc-"+a.ID.String(), start, end, summary, location, "")
		events++
	}

	for _, s := range d.Segments {
		start, end, summary, description, ok := segmentEventFieldsIn(locale, s)
		if !ok {
			continue
		}
		b.event(stamp, "seg-"+s.ID.String(), start, end, summary, "", description)
		events++
	}

	// Fallback: a datable-but-empty export still yields one trip-span event.
	if events == 0 && d.Trip.StartDate.Valid {
		end := d.Trip.StartDate.Time.AddDate(0, 0, 1)
		if d.Trip.EndDate.Valid && d.Trip.EndDate.Time.After(d.Trip.StartDate.Time) {
			end = d.Trip.EndDate.Time.AddDate(0, 0, 1)
		}
		b.event(stamp, "trip-"+d.Trip.ID.String(), d.Trip.StartDate.Time, end,
			d.Trip.Title, "", "")
	}

	b.line("END:VCALENDAR")
	return b.String()
}

// The three per-kind field resolvers below are shared by the whole-trip
// calendar and the single-event endpoint (calendar_event_handler.go) so both
// render identical all-day VEVENTs. All ends are exclusive; ok=false means the
// event is undated and gets no VEVENT.

// The three unsuffixed forms below are English-locale shims kept so
// calendar_event_handler.go (the per-event .ics) compiles unchanged; it does
// not thread a request locale yet. Follow-up: pass requestLocale there and
// delete these.

// stayEventFieldsIn resolves an accommodation's VEVENT fields: check-in through
// check-out (or one night when check-out is missing/not after check-in). The
// SUMMARY is mirrored byte-for-byte by the Flutter client's Google Calendar
// link (bookings_section.dart) — change both together.
func stayEventFieldsIn(locale string, a store.Accommodation) (start, end time.Time, summary, location string, ok bool) {
	if !a.CheckIn.Valid {
		return time.Time{}, time.Time{}, "", "", false
	}
	end = a.CheckIn.Time.AddDate(0, 0, 1)
	if a.CheckOut.Valid && a.CheckOut.Time.After(a.CheckIn.Time) {
		end = a.CheckOut.Time
	}
	return a.CheckIn.Time, end, tr(locale, "ics.stayTitle", a.Name), strPtrVal(a.Address), true
}

// segmentEventFieldsIn resolves a transport segment's VEVENT fields: departure
// day through arrival day inclusive (single day when arrival is missing). The
// SUMMARY is mirrored by the Flutter client — see stayEventFieldsIn.
func segmentEventFieldsIn(locale string, s store.TripSegment) (start, end time.Time, summary, description string, ok bool) {
	if !s.DepartDate.Valid {
		return time.Time{}, time.Time{}, "", "", false
	}
	end = s.DepartDate.Time.AddDate(0, 0, 1)
	if s.ArriveDate.Valid && s.ArriveDate.Time.After(s.DepartDate.Time) {
		end = s.ArriveDate.Time.AddDate(0, 0, 1)
	}
	summary = tr(locale, "ics.segmentTitle", localizedMode(locale, s.Mode), segmentRouteIn(locale, s))
	return s.DepartDate.Time, end, summary, strPtrVal(s.Notes), true
}

// itemEventFieldsIn resolves an itinerary item's VEVENT fields: the single trip
// day the item is assigned to. The SUMMARY is the item's own name — traveler
// data, never translated.
func itemEventFieldsIn(locale string, trip store.Trip, it store.ItineraryItem) (start, end time.Time, summary, location, description string, ok bool) {
	start, ok = itemStartDate(trip, it)
	if !ok {
		return time.Time{}, time.Time{}, "", "", "", false
	}
	return start, start.AddDate(0, 0, 1), it.Name, strPtrVal(it.Address), icsItemDescription(locale, it), true
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

// icsBuilder accumulates CRLF-terminated, RFC-folded content lines.
type icsBuilder struct {
	sb strings.Builder
}

func (b *icsBuilder) line(s string) {
	b.sb.WriteString(foldICSLine(s))
	b.sb.WriteString("\r\n")
}

// event writes one all-day VEVENT. start/end are DATE values (end exclusive).
// summary/location/description are raw text — escaped here.
func (b *icsBuilder) event(stamp, uid string, start, end time.Time, summary, location, description string) {
	b.line("BEGIN:VEVENT")
	b.line("UID:" + uid + "@goldentempo")
	b.line("DTSTAMP:" + stamp)
	b.line("DTSTART;VALUE=DATE:" + start.Format(icsDateLayout))
	b.line("DTEND;VALUE=DATE:" + end.Format(icsDateLayout))
	b.line("SUMMARY:" + escapeICSText(summary))
	if strings.TrimSpace(location) != "" {
		b.line("LOCATION:" + escapeICSText(location))
	}
	if strings.TrimSpace(description) != "" {
		b.line("DESCRIPTION:" + escapeICSText(description))
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
