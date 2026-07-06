# Plan: Free-Cap Soft Instrumentation

> **HOW.** Translates `spec.md` into a file-level technical approach. Every
> decision should trace back to an acceptance criterion. See `../../CLAUDE.md`
> for repo conventions referenced below — don't restate them, point to them.

## Technical Approach

Reuse the Wave-6 analytics seam end to end: counts come from
`analytics_events` (no migration; schema stays 00030), recording goes
through the existing fire-and-forget `recordEvent`/`recordEventOpt`
helpers, and the dashboard reads two new grouped fields off
`GET /admin/metrics`. The enforcement *template* is
`price_alert_handler.go`'s `maxActiveAlertsPerUser` +
`CountActivePriceAlertsByUser` — same shape (env-tunable cap + one count
query), but deliberately **without** the 422 branch: the count only decides
whether to emit an event. Cap values are read via the existing `envInt`
helper at call time (the `ALERT_TICK_MINUTES` pattern), which is what makes
them per-test overridable with `t.Setenv`.

## Go API Changes

`src/packages/api/` (all files are `package main`):

- **`free_cap.go` (new):** the whole feature's logic.
  - `freePlanSessionsPerMonth()` / `freeActiveTrips()` — `envInt` reads of
    `FREE_PLAN_SESSIONS_PER_MONTH` (20) / `FREE_ACTIVE_TRIPS` (3).
  - `recordPlanSessionStart(userID *uuid.UUID, authed bool)` — replaces the
    bare `go recordEventOpt(..., "plan_session_started", ...)` call in
    `planHandler`. Inside one goroutine, **in this order**: (1) if authed
    and `dbPool != nil`, run `CountEventsByTypeAndUserSince` for
    `plan_session_started` over the trailing 30 days (prior count —
    excludes this session because its own event isn't written yet); (2) if
    the prior count == cap, record `free_cap_would_hit`
    (`cap_kind=plan_runs`, `count=prior+1`); (3) record
    `plan_session_started`. Writing the would-hit *before* the started
    event makes tests deterministic: once session N's started row is
    visible, any would-hit it implies is also visible. Errors at any step
    fall through — the started event is always attempted.
  - `recordActiveTripsCapSignal(userID, tripID uuid.UUID)` — after a
    committed trip creation: `CountActiveTripLineagesByOwner`; emit iff
    count == cap+1 (`cap_kind=active_trips`, `count=n`). Nil-pool and
    error ⇒ return silently.
- **`query/analytics.sql`:** `CountEventsByTypeAndUserSince` (`:one`) and
  `FreeCapWouldHitCounts` (`:many`, GROUP BY `metadata->>'cap_kind'`,
  `count(*)` + `count(DISTINCT user_id)`).
- **`query/trips.sql`:** `CountActiveTripLineagesByOwner` (`:one`) —
  `count(DISTINCT COALESCE(chat_id, id::text))`, the same lineage key
  `ListLatestTripsByOwner`'s `DISTINCT ON` uses, so "active trips" here is
  exactly what My Trips shows.
- **`store/`:** regenerated via `make api-sqlc` (never hand-edit).
- **Call sites:**
  - `plan_handler.go` line ~113: `go recordPlanSessionStart(planUID, authed)`.
  - `plan_handler.go` `create_itinerary` branch (after `persistTrip`
    succeeds and `trip_created` is recorded): `go
    recordActiveTripsCapSignal(uid, parsed)` — async, matching the
    surrounding `go recordEvent` calls in the SSE loop.
  - `share_handler.go` `duplicateSharedTripHandler` (after commit, before
    the response is loaded): synchronous `recordActiveTripsCapSignal(user.ID,
    copyTrip.ID)` — the handler just finished a transaction, one more count
    query is negligible, and a synchronous call makes the
    exactly-one-event integration assertion deterministic. It still cannot
    fail the request (the helper swallows everything).
- **`analytics.go`:** `MetricsResponse` gains `FreeCapWouldHits` /
  `FreeCapUsersAffected` (`map[string]int64`, initialized empty);
  `adminMetricsHandler` fills them from `FreeCapWouldHitCounts` (one extra
  round trip, admin-only endpoint).
- **Guardrail:** `clientEventTypes` is untouched — `free_cap_would_hit`
  stays server-recorded only.
- **Rider — `anthropic_client.go` (new):** `newAnthropicClient(apiKey)`
  builds the client with `option.WithAPIKey` plus `option.WithBaseURL`
  when `ANTHROPIC_BASE_URL` is set. Used by both constructions
  (`plan_handler.go` ~line 94, `local_ingest_handler.go` ~line 146). The
  vendored SDK (v1.45.0) already honors `ANTHROPIC_BASE_URL` in
  `DefaultClientOptions`, but the explicit option pins the seam so it
  survives SDK upgrades and documents it at the call site.
- **`.env.sample`:** document `FREE_PLAN_SESSIONS_PER_MONTH`,
  `FREE_ACTIVE_TRIPS`, `ANTHROPIC_BASE_URL`.

## Tests

- **Unit** (`free_cap_test.go`): env parsing defaults/overrides; nil-pool
  fail-open (helpers return without panicking when `dbPool == nil`).
- **Integration** (`free_cap_integration_test.go`, `TEST_DATABASE_URL`
  harness: `resetDB` / `doJSON` / `createTestUser`, unique X-Forwarded-For
  per request):
  - **plan_runs:** `t.Setenv(FREE_PLAN_SESSIONS_PER_MONTH=2,
    ANTHROPIC_API_KEY=test, ANTHROPIC_BASE_URL=<httptest fake>)`. The fake
    Anthropic server returns a minimal `text/event-stream`
    (message_start → text delta → message_delta `end_turn` →
    message_stop), so `POST /api/v1/plan` runs a full authed session
    through `buildRouter` with zero external calls. Run 4 sequential
    sessions, polling between them until the user's
    `plan_session_started` count reaches N (the instrumentation goroutine
    is async; the would-hit-before-started ordering makes this poll
    sufficient). Assert: every response is 200 with a `text_delta` and no
    SSE `error`; after session 3 exactly one `free_cap_would_hit`
    (`cap_kind=plan_runs`, `count=3`); after session 4 still exactly one;
    dashboard shows `free_cap_would_hits.plan_runs == 1` and
    `free_cap_users_affected.plan_runs == 1`.
  - **active_trips:** `FREE_ACTIVE_TRIPS=1`; owner shares a trip; a second
    user duplicates it 3 times (each 201). Exactly one
    `free_cap_would_hit` (`cap_kind=active_trips`, `count=2`, trip id set)
    — deterministic because the duplicate-path signal is synchronous.
  - Both tests assert the crossing rule's off-by-one edges explicitly
    (cap-th unit emits nothing; cap+1-th emits; cap+2-th emits nothing).

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **`models/admin_metrics.dart`:** `freeCapWouldHits` /
  `freeCapUsersAffected` (`Map<String, int>`, default `{}`); regenerate via
  `make flutter-build-models` (with `--delete-conflicting-outputs` if
  prompted). Never hand-edit `.g.dart`.
- **`screens/admin_metrics_screen.dart`:** two tiles in the AI-planning
  grid next to "Agent loop cap hits": "Would hit plan cap" and "Would hit
  trip cap", value = crossings, caption = distinct users affected.

## Contract Parity  ← anti-drift gate

| JSON key | Go type (`analytics.go`) | Dart type (`admin_metrics.dart`) | Nullable? | ✓ |
|----------|--------------------------|----------------------------------|-----------|---|
| `free_cap_would_hits` | `map[string]int64` (always initialized) | `Map<String, int>` (default `{}`) | no | ☑ |
| `free_cap_users_affected` | `map[string]int64` (always initialized) | `Map<String, int>` (default `{}`) | no | ☑ |
