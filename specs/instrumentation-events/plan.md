# Plan: Instrumentation Events

> **HOW.** Translates `spec.md` into a file-level technical approach. See
> `../../CLAUDE.md` for repo conventions.

## Technical Approach

One append-only `analytics_events` table plus a tiny best-effort recording
helper called from existing handlers. No queue, no batching, no third party —
at this scale a synchronous insert (that swallows its own errors) is fine, and
"never fail the parent flow" is the only hard requirement. Client-side there
is exactly one event worth capturing (`booking_link_clicked`), sent
fire-and-forget from the booking-todo tap. Aggregation happens in SQL at read
time via an admin endpoint; no rollup jobs.

Key decisions:
- **Best-effort by construction:** the recorder no-ops when `dbPool` is nil
  (degraded mode) and logs-and-continues on insert error. Callers never check
  its result.
- **Server-side types can't be spoofed:** `POST /events` accepts a whitelist
  (`booking_link_clicked` only); everything else is recorded internally.
- **Metrics are computed, not stored:** a handful of aggregate queries over
  the events table, windowed by `days`. Cheap at Phase 1 volume; revisit if
  the table grows.

## Go API Changes

`src/packages/api/`:

- **Migration:** `migrations/00024_analytics_events.sql` (next after
  `00023_onboarding.sql`):
  - `analytics_events(id uuid pk default gen_random_uuid(), user_id uuid not
    null references users(id), event_type text not null, trip_id uuid null,
    metadata jsonb not null default '{}', created_at timestamptz not null
    default now())`
  - No FK on `trip_id` (events outlive trips — same rationale as
    `local_source_name` snapshots in CLAUDE.md).
  - Indexes: `(event_type, created_at)`, `(user_id, created_at)`.
- **Queries:** `query/analytics_events.sql` — `InsertAnalyticsEvent :exec`
  plus the admin aggregates (each windowed by `sqlc.arg(since)`):
  - `CountEventsByType :many` (group by event_type)
  - `CountActivatedUsers :one` (users with a `user_registered` AND a
    `trip_created` in window)
  - `CountTripsWithBookingClick :one` (distinct trip_id on
    `booking_link_clicked`)
  - `CountClicksByProvider :many` (group by `metadata->>'provider'`)
  - `CountReturningUsers :one` (users with `plan_session_started` on ≥2
    distinct days)
  - `SumPlanTokens :one` (sum `metadata->>'input_tokens'` /
    `'output_tokens'` over `plan_session_completed`)
  - Run `make api-sqlc` after.
- **Service:** new `analytics_service.go`:
  - `recordEvent(ctx, userID uuid.UUID, eventType string, tripID *uuid.UUID,
    metadata map[string]any)` — returns nothing; no-ops when `dbPool == nil`;
    `log.Printf` and continue on error. Marshal metadata to jsonb; cap the
    marshaled size (~2 KB) and drop metadata (keep the event) if exceeded.
  - `clientEventTypes` whitelist = `{"booking_link_clicked"}`.
- **Handler:** new `analytics_handler.go`:
  - `postEventHandler` — auth'd; decode `{event_type, trip_id?, metadata?}`;
    400 if type not in whitelist; call `recordEvent`; always 202 on valid
    input (even in degraded mode). Reuse `writeJSON`/`writeJSONError` and
    `userFromContext` from `auth_handler.go`.
  - `adminMetricsHandler` — parse `days` (default 30), run the aggregates,
    return one JSON summary; 503 when `dbPool == nil`.
- **Call sites** (each a one-line `recordEvent` addition):
  - `auth_handler.go` `registerHandler()` → `user_registered`
  - `auth_handler.go` `completeOnboardingHandler()` → `onboarding_completed`
  - `plan_handler.go` `planHandler()` entry (authed users only) →
    `plan_session_started` (metadata: `trip_id` when refining)
  - `plan_handler.go` at stream end → `plan_session_completed` (metadata:
    `input_tokens`, `output_tokens`, `tool_calls`, `trip_id` if produced —
    usage totals accumulated from the Anthropic responses)
  - `trip_handler.go` `persistTrip()` → `trip_created` (metadata:
    `item_count`, `chat_id`)
  - the refinement path that emits `trip_updated` SSE → `trip_refined`
  - `booking_todo_handler.go` `patchBookingTodoHandler()` → when setting
    `booked=true` → `booking_marked_booked` (metadata: `kind`, `provider`)
- **Routes:** in `main.go`, next to the existing groups:
  - `api.Handle("/events", authMiddleware(http.HandlerFunc(postEventHandler))).Methods("POST")`
  - `api.Handle("/admin/metrics", authMiddleware(adminMiddleware(http.HandlerFunc(adminMetricsHandler)))).Methods("GET")`
  - Startup log line for each.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **Service:** new `services/analytics_service.dart` — one method,
  `void trackBookingLinkClicked({required String tripId, required String
  todoId, required String provider, required String kind})`. POSTs to
  `/events` via `ApiClient`, wrapped in `unawaited(... .catchError(...))` so
  it can never block or throw into the UI. (First fire-and-forget call in the
  app — keep the pattern inside this service.)
- **Provider:** `providers/analytics_provider.dart` exposing the service off
  the existing `apiClientProvider` (one provider per feature, per CLAUDE.md).
- **Wire-up:** `screens/trip_detail_screen.dart` `_launch()` currently only
  calls `launchUrl`; extend the booking-todo open path (the `onOpen` callback
  passed to `BookingTodoCard`/`BookingTodoRow`, where `todo` and `_trip.id`
  are in scope) to call `trackBookingLinkClicked` **then** launch — launch
  must not await the track call.
- **No models / codegen:** the events POST has an empty 202 response and the
  admin metrics endpoint has no Flutter consumer — no `@JsonSerializable`
  changes, no `make flutter-build-models` needed.

## Contract Parity  ← anti-drift gate

Only one client-facing request body:

| JSON key | Go type (`analytics_handler.go`) | Dart type (`analytics_service.dart`) | Nullable? | ✓ |
|----------|----------------------------------|--------------------------------------|-----------|---|
| `event_type` | `string` | `String` | no | ☐ |
| `trip_id` | `*string` | `String?` | yes | ☐ |
| `metadata` | `map[string]any` | `Map<String, String>` | yes | ☐ |

Admin metrics response is consumed via curl only — no Dart model to keep in
parity.

## Cross-cutting

- **Env vars:** none.
- **Gateway:** new paths live under `/api/v1/` — no nginx changes.
- **Degraded mode:** matches the repo philosophy — `recordEvent` no-ops
  without a DB; `POST /events` still 202s; only `GET /admin/metrics` reports
  503.

## Verification

- `make api-fmt && make api-vet` clean; `make api-sqlc` regenerates without
  diff-noise beyond the new queries.
- `make flutter-analyze` clean (no codegen needed).
- Manual via gateway (`make docker-dev`, http://localhost:3000):
  1. Register a fresh user, complete onboarding, plan a trip to completion,
     open a booking link, mark a todo booked.
  2. `curl -H "Authorization: Bearer <admin token>" \
     'http://localhost:3000/api/v1/admin/metrics?days=1'` — expect 1 signup,
     activation 100%, 1 trip, attach rate 100%, 1 click under the provider,
     1 booked todo, ≥1 plan session with nonzero tokens.
  3. Non-admin token on the same call → 403; no token → 401.
  4. `curl -X POST .../api/v1/events` with `event_type: "user_registered"` →
     400 (server-only type rejected).
  5. Stop Postgres, repeat step 1 — every flow works identically; events
     endpoint returns 202; `/admin/metrics` returns 503.
- Walk each `spec.md` acceptance criterion.
