# Plan: Calendar Export — Timed Items & Booking Detail

> **HOW.** Translates `spec.md` into a file-level technical approach.

## Technical Approach

Two surfaces render calendar events and they must agree: the Go `.ics` builders
(whole-trip and per-event) and the **client-built Google Calendar link** in Dart.
Both were widened together.

Key decisions:

- **One `icsEvent` struct** returned by the three shared resolvers
  (`stayEventFieldsIn`, `segmentEventFieldsIn`, `itemEventFieldsIn` in
  `calendar_handler.go`), consumed by both `buildICS` and `buildSingleEventICS`.
  The UID prefixes moved *into* the resolvers so the dedupe scheme — which lets
  a single-event add collapse into a later whole-trip import — has exactly one
  definition.
- **Floating date-times** for timed items (`20260803T090000`, no `Z`, no
  `TZID`). A zone would shift the event when the traveler lands; floating is the
  correct semantic for a trip itinerary. The Dart side must match exactly, which
  is why `googleCalendarUrl` emits the same digits with no `Z`.
- **Windows are derived, not stored**: `itemTimeWindow` maps the validated
  `time_of_day` enum onto 09–12 / 13–17 / 19–22, mirrored by `_itemTimeWindow`
  in `calendar_links.dart`. No schema change. Unknown/empty ⇒ all-day.
- **`URL` is a URI value, not TEXT** (RFC 5545 §3.8.4.6) — emitted unescaped so
  query strings survive, while the same string inside `DESCRIPTION` is escaped.
- **`X-WR-CALNAME` on the whole-trip file only**; on a single-event file some
  clients offer to create a whole calendar named after that one event.
  `X-WR-TIMEZONE` is deliberately absent — it would pin the floating times.

## Go API Changes

`src/packages/api/`:

- `calendar_handler.go` — `icsEvent`, `icsDateTimeLayout`, `icsNow` (DTSTAMP
  test seam), builder `event(stamp, icsEvent)` with the DATE/DATE-TIME branch
  and the `URL` line, the three resolvers, `itemTimeWindow`,
  `icsStayDescription` / `icsSegmentDescription` / `icsDetailParts` /
  `icsBookedLabel`, `X-WR-CALNAME`.
- `calendar_event_handler.go` — `buildSingleEventICS` collapses its four-variable
  switch to one `icsEvent`; no local UID assembly.
- `i18n.go` — new `ics.booked` key (en/es).
- Reused as-is: `displayURL` (`print_view_handler.go`), `tr`, `localizedMode`,
  `localizedTimeOfDay`, `segmentRouteIn`.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- `utils/calendar_links.dart` — range resolvers now return `allDay`;
  `itemCalendarRange` takes `timeOfDay`; `googleCalendarUrl` takes `allDay`;
  new localized `stayCalendarDetails` / `segmentCalendarDetails` /
  `itemCalendarDetails` (the last moved out of `trip_detail_screen.dart`) and a
  `displayUrl` mirror of the Go helper.
- `widgets/add_to_calendar_button.dart` — new `allDay` field forwarded to the
  Google link.
- `widgets/bookings_section.dart`, `screens/trip_detail_screen.dart` — pass
  `allDay`, `timeOfDay`, and the richer detail builders.

**Wall-clock carriers:** the Dart `DateTime`s stay UTC-constructed so day
arithmetic is DST-exact, but they are never instants — no `.toLocal()`/`.toUtc()`
anywhere, because the digits are emitted without a zone. A DST test guards this.

## Contract Parity

N/A for JSON. The cross-language contract here is the *event content*: titles,
detail strings, and time windows are asserted with matching expectations in
`calendar_test.go` / `calendar_event_test.go` (Go) and `calendar_links_test.dart`
(Dart), so drift fails a test on one side.

## Cross-cutting

- **Env vars:** none new.
- **i18n:** `ics.booked` added to both locales; the catalog completeness test
  enforces coverage.

## Verification

- `make api-fmt && make api-vet`; `go test ./...`, and with `TEST_DATABASE_URL`
  for the export integration tests (incl. the updated timed assertions).
- `make flutter-analyze && make flutter-test`.
- Manual: open a trip, add an item to Google and to Apple Calendar from the same
  row, confirm identical times; import the whole-trip `.ics` and confirm the
  calendar name, item time slots, and stay booking detail.
