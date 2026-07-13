# Plan: Today Mode & Map Day-Filtering

> **HOW.** See `spec.md`. Flutter-only; no Go, endpoint, model-codegen, or env
> changes (API Surface: none). Ships in three PRs: (1) shared day-math helpers
> + `TripMap` re-fit/empty-label parameters, (2) map day-filter chips on the
> trip detail and shared screens, (3) Today auto-scroll + highlight.

## Technical Approach

All behavior derives client-side from fields the app already has
(`Trip.startDate`/`endDate`, `ItineraryItem.day`, `Accommodation.checkIn`/
`checkOut`). The design decisions, and why:

1. **Offset-reveal scroll, not `Scrollable.ensureVisible`.** The itinerary is
   a `CustomScrollView` with `sliver_tools` pinned headers; `ensureVisible`
   relies on `showOnScreen`, which is unreliable under `SliverPinnedHeader` /
   `MultiSliver` (targets land hidden beneath pinned chrome or the request is
   swallowed). Instead: resolve the target's `RenderBox` offset relative to
   the scroll view, jump/animate to that offset **minus the pinned-chrome
   height** (city header + day header compensation), then run **one
   correction pass** post-frame — expanding a collapsed section changes
   layout, so the first scroll is an estimate and the second pass fixes
   residual error. One pass only; no loops chasing layout.
2. **`GlobalKey`s keyed `'$cityKey#$day'`.** The day-header key namespace
   already exists as the collapse key (`_collapsedDays` uses `'$cityKey#$day'`
   in `trip_detail_screen.dart` `_buildGroupItemSlivers`); reusing it for a
   `Map<String, GlobalKey>` gives a stable identity per rendered day header
   without inventing a parallel scheme. Keys are created lazily per build and
   looked up by the scroller.
3. **One-shot trigger, device-local time.** "Today" =
   `tripDayOn(trip.startDate, trip.endDate, DateTime.now())` (local calendar
   date, truncated). The scroll fires once per screen visit from the first
   *non-silent* load; the silent `_refresh()` path (see chat-panel invariants)
   never re-triggers it, and it is suppressed while `_panelOpen` (refine
   panel) — a mid-conversation viewport jump would fight the user.
4. **Day filtering happens upstream of `TripMap`.** The map widget stays
   day-agnostic: the screens filter `items`/`accommodations`/`segmentLabels`
   before passing them in. Within a single day the itinerary positions are
   contiguous, so the polyline and walking-time labels stay ON — the existing
   `position + 1` adjacency guard in `TripMap` already suppresses labels and
   route continuity across gaps, so no new segment logic is needed.
5. **`fitSignature` over remount-by-key.** Re-keying `TripMap` per chip would
   re-fit for free but remounts `FlutterMap` and flashes tiles. Instead
   `TripMap` gains a defaulted `Object? fitSignature`; when it changes,
   `didUpdateWidget` re-fits post-frame via the existing `_fitToTrip`. A
   defaulted `String emptyLabel` lets the screens phrase the empty state per
   day ("No mapped places on Day 3") while the chips stay outside the map and
   thus never disappear.
6. **Checkout-exclusive stay coverage.** `stayCoversDate(checkIn, checkOut,
   date)` implements `checkIn <= d < checkOut` — the night you *sleep* there,
   so a stay never shows on its checkout day and back-to-back stays never
   double-book a night.

## Go API Changes

None.

## Flutter Changes

`src/packages/flutter-app/`:

- **PR 1 — helpers + map params (this PR):**
  - `lib/utils/trip_days.dart` (new) — pure, string-based, no model imports
    (same style as `lib/utils/trip_format.dart`):
    - `int? tripDayOn(String? startDate, String? endDate, DateTime now)` —
      truncate `now` to the local date; date-only strings parse as local
      midnight; day = `diff.inDays + 1`; null when the start is unparseable or
      the date falls outside `[1, span]`. Same formula as the former
      `_eventDayFor` in `add_to_trip_sheet.dart`.
    - `int dayCount(String? startDate, String? endDate, Iterable<int?>
      itemDays)` — max of the highest tagged day and the date span (lifted
      from `add_to_trip_sheet.dart` `_dayCount`).
    - `bool stayCoversDate(String? checkIn, String? checkOut, DateTime date)`
      — checkout-exclusive; false when either date is missing/unparseable.
  - `lib/widgets/add_to_trip_sheet.dart` — `_eventDayFor`/`_dayCount` delegate
    to the helpers (behavior-neutral; its tests pass unchanged).
  - `lib/widgets/trip_map.dart` — defaulted `Object? fitSignature` (re-fit
    post-frame in `didUpdateWidget` via `_fitToTrip`) and `String emptyLabel =
    'No mapped places'` (existing empty state). Existing call sites compile
    unchanged.
  - Tests: `test/trip_days_test.dart` (new), `test/trip_map_test.dart`
    (extended).
- **PR 2 — map chips:** chip row widget + upstream filtering and
  `fitSignature`/`emptyLabel` wiring in `trip_detail_screen.dart` and
  `shared_trip_screen.dart`; today-chip preselection on live owned trips; All
  default on shared views; row hidden when `dayCount == 0`.
- **PR 3 — Today auto-scroll:** GlobalKey registry + offset-reveal scroller +
  today highlight in `trip_detail_screen.dart`; fallback-day selection
  (nearest prior with items → nearest following → no-op); one-shot /
  refine-panel / silent-refresh guards.

## Contract Parity

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| _(none — no contract changes)_ | | | | ✓ |

## Cross-cutting

None (no env vars, routes, or gateway changes). Offline works by construction:
everything is computed from the cached trip.

## Verification

- `make flutter-analyze`, `make flutter-test` — including
  `add_to_trip_sheet_test.dart` **unchanged** (refactor is behavior-neutral).
- `test/trip_days_test.dart`: in/before/after range, day-1 and last-day
  boundaries, garbage dates, checkout-exclusive boundary, span-vs-tagged
  day count.
- Manual via `make docker-dev` → `http://localhost:3000`: walk the acceptance
  criteria in `spec.md` on a live-dated, past-dated, and undated trip, plus a
  shared link and offline view-only.
