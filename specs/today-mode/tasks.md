# Tasks: Today Mode & Map Day-Filtering

> Dependency-ordered. `[P]` = can run in parallel with its siblings (no shared
> files / no ordering dependency). Work top to bottom; verification is last.
> Flutter-only — no Go/API tasks. Ships as three PRs.

## PR 1 — Spec + day helpers + TripMap params

- [x] Copy `specs/_template/` → `specs/today-mode/`; write spec/plan/tasks
- [x] [P] `lib/utils/trip_days.dart`: `tripDayOn`, `dayCount`,
      `stayCoversDate` (pure, string-based, device-local doc comments)
- [x] [P] `lib/widgets/trip_map.dart`: defaulted `fitSignature` (post-frame
      re-fit in `didUpdateWidget`) + `emptyLabel` params
- [x] Refactor `add_to_trip_sheet.dart` `_eventDayFor`/`_dayCount` to delegate
      to the helpers (behavior-neutral)
- [x] `test/trip_days_test.dart`: range boundaries, garbage dates,
      checkout-exclusive boundary, span-vs-tagged day count
- [x] Extend `test/trip_map_test.dart`: custom `emptyLabel` renders;
      `fitSignature` change smoke test

## PR 2 — Map day-filter chips

- [ ] Day-chip row widget (`All · Day 1…N`), hidden when `dayCount == 0`
- [ ] Upstream filtering in `trip_detail_screen.dart`: items by `day`, stays
      by `stayCoversDate` (checkout-exclusive night), segment labels to match
- [ ] Wire `fitSignature` (selected day) + per-day `emptyLabel`; chips live
      outside the map so an empty day never hides them
- [ ] Undated items only under All; live trips preselect today's chip
- [ ] `shared_trip_screen.dart`: same chips defaulting to All, no Today
      behaviors
- [ ] Widget tests: filtering, empty-day message, chip-row visibility rules

## PR 3 — Today auto-scroll + highlight

- [ ] `Map<String, GlobalKey>` registry keyed `'$cityKey#$day'` on day headers
- [ ] Offset-reveal scroller: pinned-chrome compensation + one correction pass
- [ ] Expand collapsed city/day sections containing the target before scrolling
- [ ] Fallback: today-with-no-items → nearest prior day with items → nearest
      following → no-op
- [ ] One-shot guard: first non-silent load only; never on silent `_refresh()`,
      never while the refine panel is open; today highlight on the day header
- [ ] Widget tests: auto-scroll happy path, fallbacks, guards, undated/past
      trips unchanged

## Verification

- [x] `flutter analyze --no-fatal-infos --fatal-warnings` clean (no new infos)
- [x] `make flutter-test` passes, including `add_to_trip_sheet_test.dart`
      unchanged (PR 1)
- [ ] Manual end-to-end via gateway (`make docker-dev` →
      `http://localhost:3000`): every acceptance criterion in `spec.md` on
      live-dated / past / undated trips, a shared link, and offline (PRs 2–3)
