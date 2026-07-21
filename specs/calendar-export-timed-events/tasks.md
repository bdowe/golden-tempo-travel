# Tasks: Calendar Export — Timed Items & Booking Detail

> Dependency-ordered. `[P]` = can run in parallel with its siblings.

## API (Go)

- [x] `icsEvent` struct + `icsDateTimeLayout` + `icsNow` seam
- [x] Builder `event(stamp, icsEvent)`: DATE vs floating DATE-TIME, `URL` line
      emitted unescaped (URI value type)
- [x] Resolvers return `(icsEvent, bool)` carrying UID/AllDay/URL/Description
- [x] `itemTimeWindow` (09–12 / 13–17 / 19–22; unknown ⇒ all-day)
- [x] `icsStayDescription` / `icsSegmentDescription` reusing `displayURL`
- [x] `X-WR-CALNAME` on the whole-trip calendar only
- [x] `ics.booked` catalog key (en/es)
- [x] `buildSingleEventICS` consumes the shared `icsEvent`

## UI (Flutter)

- [x] `calendar_links.dart`: `allDay` on all range resolvers, `timeOfDay` on
      `itemCalendarRange`, `allDay` on `googleCalendarUrl` (no `Z`)
- [x] Localized detail builders + `displayUrl` mirror
- [x] `AddToCalendarButton.allDay`; wire bookings rows and the item menu

## Tests

- [x] [P] Go `calendar_test.go`: time windows, descriptions, timed-vs-all-day,
      URL-not-escaped, **first real `foldICSLine` tests** (300-char ASCII,
      2-byte and 4-byte runes), pinned-DTSTAMP whole document
- [x] [P] Go `calendar_event_test.go`: timed item, all-day fallback, stay and
      segment booking detail, bare event emits neither DESCRIPTION nor URL
- [x] `export_integration_test.go`: timed item assertions + `X-WR-CALNAME`
- [x] Dart `calendar_links_test.dart`: floating timed link, per-bucket hours,
      all-day fallbacks, **DST guard**, detail builders, `displayUrl`

## Verification

- [x] `gofmt`/`go vet` clean; full Go suite green with `TEST_DATABASE_URL`
- [x] `flutter analyze` clean (no new issues); 416 Flutter tests green
- [ ] Manual end-to-end via gateway: same-row Google vs Apple parity, whole-trip
      import shows calendar name + time slots + booking detail
