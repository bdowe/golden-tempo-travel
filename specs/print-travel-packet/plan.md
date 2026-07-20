# Plan: Print Travel Packet

> **HOW.** Translates `spec.md` into a file-level technical approach. Every
> decision should trace back to an acceptance criterion. See `../../CLAUDE.md`
> for repo conventions referenced below — don't restate them, point to them.

## Technical Approach

Rebuild the body of the existing token-gated print page
(`print_view_handler.go`) as a day-by-day packet. All changes are server-side
Go; the Flutter trigger flow (`_openPrintExport` → mint token → new tab) is
untouched.

Key decisions:

- **`loadExportData` stays frozen.** It is shared with the trip-review engine
  (`review_handler.go`) and a plan tool (`plan_tools_extra.go`); both load
  budget themselves and neither wants weather-lookup latency. Budget and
  weather for print load in `printViewHandler` only, best-effort — a failure
  omits the section, never 500s a page whose headers may already be sent.
- **Day assembly is pure functions** over `exportData`, unit-testable without
  a DB: bucket items by `day`, attach segments by depart/arrive date, match
  stays by `check_in ≤ night < check_out`.
- **A `maxPrintDays = 60` clamp** guards the new 1..N day loop — the old code
  never iterated a range, so a stray `day = 5000` was harmless; now it must be
  clamped (over-clamp items land in Unscheduled).
- **Weather uses the trip-review idiom** (`weatherDayKey`, forecast exact-date
  vs historical MM-DD matching), bounded by a 6-second context and a 5-city
  cap; the day→city mapping comes from the day's items with gap-fill from the
  previous day.
- **URLs print as visible text** (`host+path`, truncated) because paper isn't
  clickable; `html/template` discipline is preserved (no Sprintf HTML).

## Go API Changes

`src/packages/api/` (all files are `package main`):

- **Routes:** none — `GET /export/{token}/print.html` already registered.
- **Handlers:** all work in `print_view_handler.go`:
  - view models: `printDaySection`, `printBudget`/`printBudgetRow`; extended
    `printItem` (+City), `printSegment` (+Provider/PriceNote/Notes/URL/
    URLText/Booked), `printStay` (+Provider/PriceNote/URL/URLText/Booked/Note)
  - pure builders: `printDayCount`, `resolveDayCities`, `buildPrintDays`,
    `buildPrintBudget`, `displayURL`, `formatWeatherLine`; rewritten
    `buildPrintView(d, budget, weatherByDay)`
  - loaders: `loadPrintBudget` (GetBudgetByTrip/ListExpensesByTrip, nil on
    error), `loadPrintWeather` (takes `*WeatherService` param for testability)
  - template: day sections → Unscheduled → Other transport / Accommodations
    fallback lists → Budget → Booking checklist → Packing checklist; print CSS
    `break-inside: avoid` on day sections/rows, `@page { margin: 14mm }`
- **Service:** none new — reuses `weatherService` and sqlc `store` queries.
- **Types:** view models above, template-only (no JSON).

Unchanged: `export_handler.go`, `export_token.go`, `calendar_handler.go`,
`review_handler.go`, `plan_tools_extra.go`.

## Flutter Changes

**None.** The existing menu action, token mint, and URL builder work as-is.

## Contract Parity  ← anti-drift gate

N/A — the page is server-rendered HTML; no JSON contract changes on either
side.

## Cross-cutting

- **Env vars:** none new (`EXPORT_SIGNING_SECRET` already documented).
- **Gateway:** existing path, no proxy changes.

## Verification

(Mirror into `tasks.md` as the final tasks.)

- `make api-fmt && make api-vet` — clean.
- `go test ./...` in `src/packages/api` (unit); with `TEST_DATABASE_URL` for
  the export integration tests, including untouched `TestExportCalendar_*`.
- Manual via `make docker-dev` (API container needs `up --build`): open a trip
  → menu → "Print / Save as PDF" → walk the acceptance criteria in `spec.md`,
  then Cmd+P to check page breaks.
