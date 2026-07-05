# Tasks: Price Alerts

## PR 1 — API (`price-alerts-api`)
- [x] Spec + plan
- [ ] Migration `00029_price_alerts.sql` + `query/price_alerts.sql` + sqlc
- [ ] `price_alert_checker.go` (ticker, grouping, evaluateAlert, email)
- [ ] `price_alert_handler.go` (POST/GET/PATCH/DELETE `/alerts`) + routes
- [ ] Metrics counts (`alerts_created`/`alerts_triggered`)
- [ ] Pure + stub-Duffel + integration tests; `.env.sample` knobs

## PR 2 — Flutter (`price-alerts-flutter`)
- [ ] `price_alert.dart` model + codegen
- [ ] `alerts_api_service.dart` + `alerts_provider.dart`
- [ ] `alerts_screen.dart` + `create_alert_sheet.dart`
- [ ] "Watch this route" on flight search; account-menu entry; `/alerts` deep link
- [ ] Widget + model tests

## Deferred (spec Out of Scope)
- Child passengers, date ranges, push channel, read/unread, paid gating,
  multi-instance checker coordination.
