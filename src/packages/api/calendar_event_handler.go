package main

import (
	"net/http"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
)

// calendar_event_handler.go — GET /api/v1/export/{token}/event/{kind}/{id}.ics,
// one trip event as a single-VEVENT iCalendar file so it can be added to Apple
// (or any other) calendar individually. Token-gated and PUBLIC like the
// whole-trip calendar.ics; kind ∈ stay|segment|item. UIDs match the whole-trip
// export so re-adding after a full-trip import dedupes in the user's calendar.

// calendarEventHandler streams a single trip event's .ics attachment.
func calendarEventHandler(w http.ResponseWriter, r *http.Request) {
	vars := mux.Vars(r)
	notFound := func() {
		// Match the whole-trip route: opaque 404, no leak — bad token, bad id,
		// unknown kind, and undated event are all indistinguishable.
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("export link not available"))
	}
	data, ok := resolveExport(r, vars["token"])
	if !ok {
		notFound()
		return
	}
	id, err := uuid.Parse(vars["id"])
	if err != nil {
		notFound()
		return
	}
	body, filename, ok := buildSingleEventICS(requestLocale(r.Context()), data, vars["kind"], id)
	if !ok {
		notFound()
		return
	}
	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", `attachment; filename="`+filename+`.ics"`)
	w.Write([]byte(body))
}

// buildSingleEventICS finds the event by kind+id in the export snapshot and
// renders a one-VEVENT VCALENDAR. ok=false for an unknown kind, a missing id,
// or an undated event — callers answer one opaque 404 for all of them.
func buildSingleEventICS(locale string, d exportData, kind string, id uuid.UUID) (body, filename string, ok bool) {
	// The UID comes from the resolver, so the dedupe scheme has exactly one
	// definition shared with the whole-trip export.
	var ev icsEvent
	switch kind {
	case "stay":
		for _, a := range d.Accommodations {
			if a.ID == id {
				ev, ok = stayEventFieldsIn(locale, a)
				break
			}
		}
	case "segment":
		for _, s := range d.Segments {
			if s.ID == id {
				ev, ok = segmentEventFieldsIn(locale, s)
				break
			}
		}
	case "item":
		for _, it := range d.Items {
			if it.ID == id {
				ev, ok = itemEventFieldsIn(locale, d.Trip, it)
				break
			}
		}
	}
	if !ok {
		return "", "", false
	}

	var b icsBuilder
	b.line("BEGIN:VCALENDAR")
	b.line("VERSION:2.0")
	b.line("PRODID:-//Golden Tempo Travel//Trip Export//EN")
	b.line("CALSCALE:GREGORIAN")
	b.line("METHOD:PUBLISH")
	// No X-WR-CALNAME here: on a single-event file some clients offer to create
	// a whole new calendar named after that one event.
	stamp := icsNow().UTC().Format("20060102T150405Z")
	b.event(stamp, ev)
	b.line("END:VCALENDAR")
	return b.String(), tripSlug(ev.Summary), true
}
