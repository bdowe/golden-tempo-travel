# Plan: Offline Trip Cache

> Flutter-only. No Go API changes, no schema changes, no new endpoints.

## Technical Approach

Write-through cache at the service/provider seam, read on network failure
only. On every successful `listTrips()` / `getTrip()` the payload is written
(fire-and-forget, `unawaited`) to `shared_preferences` under user-scoped keys
— the same storage and keying convention as `recent_trip_provider.dart`. When
a fetch throws a **network-level** error, the caller reads the cache and, on
a hit, renders it read-only with an offline banner.

Key decisions:

- **shared_preferences, not a DB (v1).** Matches the existing on-device
  storage pattern; zero new dependencies; web backing is localStorage. Trip
  JSON is small (tens of KB); the 10-trip LRU cap bounds total size. The size
  trade-off is documented in the spec; a drift/sqflite upgrade slots in
  behind the same `TripCache` API later.
- **Network-error classification, not connectivity plugins.** `package:http`
  ≥1.0 wraps all socket/IO failures in `http.ClientException`; timeouts are
  `TimeoutException`. HTTP non-200s in `TripsApiService` are thrown as plain
  `Exception('… (status)')` and therefore never classify as network errors —
  so 403/404/500 can never fall back to cache. Classifier:
  `TripCache.isNetworkError(e)` = `ClientException || TimeoutException ||
  toString contains 'SocketException'` (belt-and-braces for raw dart:io
  errors; `dart:io` itself is not importable on web).
- **Online path untouched.** The only additions on success are (a) an
  `unawaited` cache write and (b) clearing the `offlineSince` marker. No new
  awaits before state updates, no changes to `_load(silent:)`, `_refresh()`
  coalescing, `tripUpdateCount`, or any chat-panel behavior (PRs #51/#53
  invariants). Cache fallback happens only inside existing `catch` blocks,
  and only on the **loud** path (`!quiet`) — silent-refresh failures keep
  their "stay quiet, keep stale trip" behavior.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **`services/trip_cache.dart`** (new) — `TripCache(userId)`:
  - Keys: `trip_cache.<userId>.list`, `trip_cache.<userId>.trip.<tripId>`,
    `trip_cache.<userId>.index` (MRU list of trip ids for eviction).
  - `writeList / readList` and `writeTrip / readTrip`; payloads are
    `{saved_at: ISO-8601, …Trip.toJson()}`; reads return a
    `(value, savedAt)` record or null on any parse error.
  - `writeTrip` bumps the id to the front of the MRU index and evicts beyond
    `maxCachedTrips = 10` (removes the evicted trips' keys).
  - `removeTrip(id)` — called on trip deletion; also drops the trip from the
    cached list payload.
  - All writes swallow exceptions (best-effort); `userId == null` no-ops.
  - `static clearForUser(userId)` — removes every `trip_cache.<userId>.` key.
  - `static isNetworkError(Object)` — the classifier above.
- **`providers/trip_cache_provider.dart`** (new) — provides `TripCache`
  scoped to `authProvider`'s user id (same pattern as `recentTripProvider`).
- **`providers/trips_provider.dart`** — `TripsState` gains
  `DateTime? offlineSince` (null = live data). `TripsNotifier` takes the
  cache; `loadTrips()` success → `offlineSince: null` + unawaited
  `writeList`; failure → if network error and cache hit, serve cached trips
  with `offlineSince`; otherwise the existing error path, verbatim.
  `deleteTrip()` additionally calls unawaited `removeTrip(id)`.
- **`widgets/offline_banner.dart`** (new) — "Offline — showing saved copy
  from <relative time>" + Retry button; exposes a testable
  `relativeTime(DateTime, {DateTime? now})` helper.
- **`screens/trips_list_screen.dart`** — when `state.offlineSince != null`,
  pin `OfflineBanner` above the body (Retry = `loadTrips()`).
- **`screens/trip_detail_screen.dart`** (surgical) —
  - New field `DateTime? _offlineSince`; getter `_isOffline`.
  - `_load()`: success block clears `_offlineSince` and unawaited-writes the
    trip to cache (before the existing follow-ups; `recentTripProvider`
    recording unchanged). Catch block: when `!quiet` and
    `isNetworkError(e)`, read cache; on hit set `_trip`/`_bookingTodos` from
    the copy + `_offlineSince`, and skip the network follow-ups
    (todo sync / travel times / prefs) — they already only run on live
    success. On miss fall through to the existing error handling, verbatim.
  - Banner: wrap the existing `refreshable` in a Column with `OfflineBanner`
    (Retry = loud `_load()`) when offline-serving.
  - Mutations: hide owner appbar actions (share/delete) while offline;
    disable header affordances (rename, dates, status, Refine with AI) and
    "Add place"/"Add booking"; a one-line `_guardOffline()` (snackbar +
    early-return) at the top of every mutation method — `_openRefine`,
    `_editTitle`, `_editDates`, `_patch`, `_delete`, `_addPlace`,
    `_addBooking`, `_setBooked`, `_deleteTodo`, `_addStay`, `_deleteStay`,
    `_addSegment`, `_deleteSegment`, `_editItem`, `_deleteItem`,
    `_reorderSection` — covers deep entry points (item menus, todo cards,
    per-day/city refine icons) without touching their widget subtrees.
- **`providers/auth_provider.dart`** — `signOutLocally()` (the shared funnel
  for logout, sign-out-everywhere, and account deletion) captures the user id
  before clearing state and calls `TripCache.clearForUser(userId)`.

## Contract Parity

No wire contract changes; the cache round-trips the existing
`Trip.toJson()`/`Trip.fromJson()` pair (json_serializable, already in parity
with the Go API).

## Cross-cutting

- No new env vars, no gateway changes, no new packages
  (`shared_preferences` is already a dependency).
- Chat invariants (PRs #51/#53): untouched — no changes to
  `plan_provider.dart`, `chat_panel.dart`, `trip_refine_panel.dart`;
  `_refresh()`/`_load(silent:)` logic byte-identical; the refine panel can
  never open while offline-serving (`_openRefine` guard) so its listeners
  never observe cached state.

## Verification

- `flutter analyze` clean (no new infos); `make flutter-test` green.
- New tests:
  - `test/trip_cache_test.dart` — round-trip, savedAt, LRU eviction at 10,
    per-user isolation, corrupt-entry miss, `clearForUser`, classifier.
  - `test/trips_provider_offline_test.dart` — network error → cache serve
    with `offlineSince`; HTTP-status error → no fallback; success clears
    offline state + writes through; delete removes cache entry.
  - `test/trip_detail_offline_test.dart` — widget: banner text, disabled
    mutation affordances, no share/delete actions, retry exits offline mode;
    403 shows error page not cache.
  - `test/trips_list_offline_test.dart` — widget: banner over cached list.
- Existing `trip_detail_silent_refresh_test.dart` must pass unmodified
  (proves the silent path didn't change).
- Manual airplane-mode walk-through (requires a device/browser; listed in the
  PR): load list + a trip online → go offline → relaunch → verify banner,
  read-only, retry; sign out offline → cache gone after re-login.
