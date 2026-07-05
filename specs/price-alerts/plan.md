# Plan: Price Alerts

> HOW. See `spec.md` for what/why.

## Overview

Three pieces: a `price_alerts` table + sqlc queries; an in-process checker
(`price_alert_checker.go`) that periodically re-searches watched routes via
the existing `duffelService` and emails through the existing `emailService`;
and a small authenticated CRUD surface (`price_alert_handler.go`). Flutter UI
ships separately (see tasks.md) — service/provider/screen cloned from the
booking-todos and flights patterns.

## Data

Migration `00029_price_alerts.sql`: table per spec.md's data model.
`DOUBLE PRECISION` for prices (sqlc → `*float64`, matching
`FlightOffer.Price`; cent precision irrelevant for display+thresholds).
Partial unique index on `(user_id, origin, destination, depart_date,
COALESCE(return_date,'0001-01-01'), cabin_class, adults) WHERE status =
'active'` enforces no-duplicate-active. Due-list index
`(last_checked_at NULLS FIRST) WHERE status = 'active'`.

`query/price_alerts.sql`: CreatePriceAlert, ListPriceAlertsByUser,
GetPriceAlertForUser (id+user ownership in SQL, like booking_todos),
CountActivePriceAlertsByUser, UpdatePriceAlert (status/target),
DeletePriceAlert (:execrows), ListDuePriceAlerts (freshness cutoff + LIMIT),
MarkPriceAlertChecked, MarkPriceAlertNotified, ExpirePastPriceAlerts.

## Checker (`price_alert_checker.go`)

`alertChecker{duffel *DuffelService, interval, checkEvery time.Duration,
batchSize int, perCallGap time.Duration}`; `startAlertChecker(ctx)` called
from `main()` after DB init. Disabled (with a log line) when `dbPool == nil`
or the Duffel token is empty — CRUD stays available either way.

Per tick (`runOnce`, the testable unit):
1. `ExpirePastPriceAlerts`.
2. `ListDuePriceAlerts(now-checkEvery, batchSize)` (batch 25 default).
3. Group by `alertSearchKey(alert)` = origin|dest|dates|cabin|adults —
   N watchers of one route cost one Duffel search per cycle.
4. Per group: `duffel.SearchFlightOffers`, `lowestOffer(offers)`, sleep
   `perCallGap` (1s) between groups. On Duffel error: log, do NOT mark
   checked (retries next tick).
5. Per alert: `evaluateAlert(alert, lowest, currency)` (pure):
   - currency mismatch with stored currency → record only, never notify;
   - target mode: notify when `lowest <= target` and (never notified or
     `lowest < lastNotified - epsilon`);
   - any-drop mode: first check records baseline; notify when lowest is
     ≥5% AND ≥$5 below baseline and below lastNotified by the same margin.
   Then `MarkPriceAlertChecked`; on notify `MarkPriceAlertNotified` BEFORE
   sending (idempotency even if the send crashes), then `sendAlertEmail`
   (fire-and-forget goroutine, `publicAppURL("alerts")` deep link, pattern
   from `email_auth_handler.go`) and `recordEvent("alert_triggered")`.

Startup jitter (random fraction of interval) before the first tick. Env
knobs: `ALERT_TICK_MINUTES` (default 5), `ALERT_CHECK_HOURS` (default 6),
documented in `.env.sample`. Single-process by design; if the API ever runs
multi-instance, add `FOR UPDATE SKIP LOCKED` to ListDuePriceAlerts.

## Handlers (`price_alert_handler.go`)

Clone of the booking-todo handler shapes. Routes in `buildRouter()`:
POST `/alerts` under `strict(authMiddleware(...))`; GET/PATCH/DELETE under
`authMiddleware`. Pure `validateCreateAlert` (mirrors flight search
validation: IATA regex, date parse + not past, `allowedCabinClasses`,
adults 1–9, target > 0). Cap: `CountActivePriceAlertsByUser >= 10` → 422
(future paid gate — see business-model §4). Duplicate active → 409 (the
partial unique index backs this; map the pg unique violation).
`recordEvent("alert_created")` on success. 503 when `dbPool == nil`.

`analytics.go`: `AlertsCreated`/`AlertsTriggered` counts (event-type counts)
in `MetricsResponse`.

## Tests

Pure: `evaluateAlert` (target crossed / re-check same price / further drop /
any-drop thresholds / currency mismatch / nil-baseline first check),
`alertSearchKey` grouping, `lowestOffer`, `buildAlertEmail` (subject/body/
link with `t.Setenv(PUBLIC_BASE_URL)`), `validateCreateAlert`.
Duffel-facing: stub `httptest.NewServer` returning canned offers, injected
via `&DuffelService{Token, BaseURL}` (pattern: `duffel_service_test.go`).
Integration (harness from the handler-test-suite PR): create → list →
duplicate 409 → cap 422 → patch pause → delete, plus cross-user 404.

## Flutter (separate PR)

`models/price_alert.dart` (+codegen), `services/alerts_api_service.dart`,
`providers/alerts_provider.dart`, `screens/alerts_screen.dart`,
`widgets/create_alert_sheet.dart`; entry points: "Watch this route" button
on flight search results (signed-in only), account-menu item, `/alerts`
deep link. Patterns: booking_todos service, flights provider, StatusPill/
EmptyState widgets.
