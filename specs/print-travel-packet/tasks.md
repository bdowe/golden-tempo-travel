# Tasks: Print Travel Packet

> Dependency-ordered. `[P]` = can run in parallel with its siblings (no shared
> files / no ordering dependency). Work top to bottom; verification is last.

## API (Go)

- [ ] Extend/add view models in `print_view_handler.go` (`printDaySection`,
      `printBudget`, richer `printSegment`/`printStay`/`printItem`)
- [ ] Pure builders: `printDayCount` (60-day clamp), `resolveDayCities`,
      `buildPrintDays`, `buildPrintBudget`, `displayURL`, `formatWeatherLine`
- [ ] Rewrite `buildPrintView` to assemble days + unscheduled + fallback lists
- [ ] Rewrite `printViewTmpl`: summary → day sections → Unscheduled → Other
      transport / Accommodations → Budget → checklists; print CSS page-break
      rules
- [ ] Handler loaders: `loadPrintBudget`, `loadPrintWeather` (best-effort,
      6s timeout, ≤5 cities); wire into `printViewHandler`
- [ ] Confirm zero diffs in `export_handler.go`, `calendar_handler.go`,
      `review_handler.go`, `plan_tools_extra.go`

## Models & codegen (Flutter)

- N/A — no Flutter changes (server-rendered HTML, trigger flow unchanged)

## Tests

- [ ] [P] Unit `print_view_test.go`: `buildPrintDays` edge cases (stay-night
      matching, check-in/out notes, arrive-only segments, undated trip,
      day clamp, day-trip labels, empty days), `buildPrintBudget`,
      `displayURL`, `formatWeatherLine`, template escaping,
      `loadPrintWeather` via `weatherStub` + dead-server resilience
- [ ] Integration `export_integration_test.go`: extend fixture (summary,
      budget+expenses, booked segment with URL, unscheduled item, empty day),
      swap `weatherService` stub; keep `TestExportCalendar_*` and existing
      print assertions green

## Verification

- [ ] `make api-fmt && make api-vet` clean
- [ ] `go test ./...` in `src/packages/api`; full suite with
      `TEST_DATABASE_URL`
- [ ] Manual end-to-end via gateway (`make docker-dev` →
      `http://localhost:3000`): every acceptance criterion in `spec.md`
      checked off; Cmd+P page-break check
