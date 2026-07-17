# Plan: Price Alerts v2 — Notification Center & Flexible Dates

> **HOW.** Translates `spec.md` into a file-level technical approach. See
> `../../CLAUDE.md` for repo conventions. Builds directly on
> `specs/price-alerts/plan.md` (v1) — the checker, thresholds, and CRUD
> surface are unchanged unless named here.

## Technical Approach

Three PRs, each independently shippable:

1. **PR 1 — alert events (API spine).** A new `alert_events` table written
   by the checker inside the same idempotent block that marks an alert
   notified (`MarkPriceAlertNotified` runs first, so a crash can lose the
   event/email but never duplicate them — same tradeoff v1 chose for email).
   Three small authed read endpoints. No new service; the handler reads
   sqlc-generated queries directly, like `price_alert_handler.go`.
2. **PR 2 — Flutter notification center.** Bell + badge in the app shell,
   list screen, mark-all-read on open. Pure client of PR 1.
3. **PR 3 — flexible dates.** `flex_days` column (0–3) on `price_alerts`;
   the checker fans one watched route out to the date window with the
   existing per-cycle budget accounting.

Key decision: **events are denormalized with `user_id`** (analytics-events
convention) so the feed and badge are single-table scans under
`(user_id, occurred_at DESC)` / partial unread indexes — the price_alerts
join happens only in the feed query, for display context.

## Go API Changes (PR 1 — shipped with this spec)

`src/packages/api/`:

- **Migration `migrations/00033_alert_events.sql`:** `alert_events` table —
  `id`, `alert_id` (FK → price_alerts, CASCADE), `user_id` (FK → users,
  CASCADE, denormalized), `price` / `previous_price` (DOUBLE PRECISION to
  match `price_alerts`; sqlc emits `*float64`), `currency`, `occurred_at`,
  nullable `read_at`. Indexes: `(user_id, occurred_at DESC)` for the feed;
  partial `(user_id) WHERE read_at IS NULL` for the badge.
- **Queries `query/alert_events.sql`:** `InsertAlertEvent`,
  `ListAlertEventsByUser` (inner-join `price_alerts` for route/dates
  context, `ORDER BY occurred_at DESC, id DESC LIMIT $2`),
  `MarkAlertEventsRead` (all-for-user; the by-id variant was considered and
  deferred — see spec Decisions), `CountUnreadAlertEvents`. Regenerate with
  `make api-sqlc`.
- **Checker `price_alert_checker.go`:** in `settle`, after
  `MarkPriceAlertNotified` succeeds, `InsertAlertEvent` with the same values
  the email gets; `previous_price` comes from `alertReferencePrice`
  (last-notified else baseline — the same fixed reference `evaluateAlert`
  judged against, read from the pre-settle row). Best-effort: failure logs
  and the loop continues.
- **Handlers `alert_events_handler.go`:** `listAlertEventsHandler`
  (`limit` default 50, cap 200), `markAlertEventsReadHandler` (204),
  `unreadAlertEventsCountHandler` (`{"count": N}`). All behind
  `authMiddleware`; 503 in degraded mode like the rest of the alerts
  surface.
- **Routes `main.go`:** `GET /alerts/events`, `POST /alerts/events/read`,
  `GET /alerts/events/unread-count`, registered before `/alerts/{id}` so
  `events` is never captured as an id.
- **Types:** `AlertEventResponse` (event + joined alert context) in
  `alert_events_handler.go`; `PriceAlertResponse` gains `baseline_price`.

## Go API Changes (PR 3 — future)

- Migration `000xx_price_alert_flex.sql`: `flex_days INT NOT NULL DEFAULT 0`
  + `CHECK (flex_days BETWEEN 0 AND 3)`; the v1 active-duplicate unique
  index is unaffected (same exact-search key; flexibility is an attribute of
  the watch, not the identity).
- `validateCreateAlert`: accept/clamp-reject `flex_days` (422 above 3).
- Checker: `alertSearchKey` gains flex_days; a flexible alert expands to
  `2*flex+1` dated searches. Budgeting: each expanded date counts against
  `alertBatchSize` (the per-cycle cap bounds provider calls, not alert
  rows), and route-dedupe applies per expanded date. Trigger evaluates the
  minimum across the window; email/event body names the winning date
  (extend `buildAlertEmail` + store the found date on the event —
  `found_depart_date DATE NULL` added in the same migration).

## Flutter Changes (PR 2 — future)

`src/packages/flutter-app/lib/`:

- **Models:** `alert_event.dart` (`@JsonSerializable`, matches
  `AlertEventResponse`), then `make flutter-build-models`.
- **Service:** extend the alerts service with `listEvents`, `markAllRead`,
  `unreadCount`.
- **Provider:** `alert_events_provider.dart` — feed list + unread count;
  refresh on app resume and after mark-all-read.
- **UI:** bell + badge in the `AppShell` nav (design-system conventions:
  reuse `EmptyState`, `StatusPill`); `notification_center_screen.dart` list;
  mark-all-read fired on open.

## Contract Parity  ← anti-drift gate

Filled for PR 1's response (Dart column checked in PR 2):

| JSON key | Go type (`alert_events_handler.go`) | Dart type (PR 2) | Nullable? | ✓ |
|----------|--------------------------------------|------------------|-----------|---|
| `id` | `string` | `String` | no | ☐ |
| `alert_id` | `string` | `String` | no | ☐ |
| `price` | `float64` | `double` | no | ☐ |
| `currency` | `string` | `String` | no | ☐ |
| `previous_price` | `*float64` | `double?` | yes | ☐ |
| `occurred_at` | `string` (RFC3339) | `String` | no | ☐ |
| `read_at` | `*string` (RFC3339) | `String?` | yes | ☐ |
| `origin` | `string` | `String` | no | ☐ |
| `destination` | `string` | `String` | no | ☐ |
| `depart_date` | `string` (YYYY-MM-DD) | `String` | no | ☐ |
| `return_date` | `*string` | `String?` | yes | ☐ |
| `target_price` | `*float64` | `double?` | yes | ☐ |
| `alert_status` | `string` | `String` | no | ☐ |
| `baseline_price` (on alerts) | `*float64` | `double?` | yes | ☐ |
| `count` (unread) | `int64` | `int` | no | ☐ |

## Cross-cutting

- **Env vars:** none new.
- **Gateway:** new paths live under `/api/v1/` — no proxy changes.
- **resetDB:** `alert_events` added to the integration TRUNCATE list.

## Verification

- `make api-sqlc` (committed clean), `make api-fmt && make api-vet`,
  `go test ./...`.
- Integration (TEST_DATABASE_URL): checker inserts exactly one event per
  trigger with the email's values, none on non-drop or unchanged re-check;
  feed returns joined context newest-first; unread-count reflects
  mark-all-read; cross-user isolation; alert-delete cascade.
- PR 2: `make flutter-build-models`, `make flutter-analyze`,
  `make flutter-test`; manual walk of the badge → open → clear flow via
  `make docker-dev`.
