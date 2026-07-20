# Tasks: Spanish Localization (i18n)

> Dependency-ordered by PR. `[P]` = parallelizable with its siblings.
> Spanish stays invisible to users until PR 7, so PRs 1-6 ship independently.

## PR 1 — Server locale foundation

- [x] Write `spec.md` + `plan.md`
- [x] Migration `00049_user_locale.sql` (`users.locale TEXT`, nullable)
- [x] `query/users.sql`: `UpdateUserProfile` partial-update query; `make api-sqlc`
- [x] `i18n.go`: `supportedLocales`, `normalizeLocale`, `matchLocale`,
      `localeMiddleware`, `requestLocale`, `tr`, `localizedDate`, `languageName`
- [x] Register `localeMiddleware` in `main.go`
- [x] `patchAccountHandler` accepts + validates `locale`
- [x] `UserResponse`/`toUserResponse` expose `locale`
- [x] Unit tests: locale matching, catalog fallback + completeness, dates
- [x] Integration test: locale round-trips PATCH → `/auth/me`; invalid rejected
- [x] `make api-fmt && make api-vet` clean

## PR 2 — Flutter i18n infrastructure

- [x] `pubspec.yaml`: `flutter_localizations`, `intl`, `generate: true`
- [x] `l10n.yaml` + `lib/l10n/app_en.arb` + `lib/l10n/app_es.arb` (shell strings)
- [x] `lib/l10n/l10n.dart` — `context.l10n` extension + `kSupportedLocales`
      (single source of truth; `es` added here in PR 7)
- [x] `lib/providers/locale_provider.dart` — override persistence, effective
      locale, `Intl.defaultLocale`, account sync
- [x] `main.dart` — delegates, `supportedLocales: [en]` (es deferred to PR 7)
- [x] `services/api_client.dart` — `Accept-Language` in `jsonHeaders()`;
      `account_api_service.dart` — `updateLocale`
- [x] Auth user model gains `locale`; `make flutter-build-models`
- [x] [P] `utils/trip_format.dart` → `DateFormat` (signatures unchanged)
- [x] [P] `utils/money_format.dart` → `NumberFormat` digit grouping
- [x] Tests: locale resolution, `Accept-Language` header, Spanish date/number
      formatting; `flutter analyze` CI-clean; 395 tests pass
- [x] CI gate: `flutter gen-l10n` + untranslated-messages check + l10n drift
      check (mirrors the Go sqlc drift check)

## PRs 3-5 — String extraction (mechanical)

**PR 3 (batch A) is DONE**: preferences, auth, reset-password, landing, verify,
sso-callback, account-settings, onboarding-quiz + the three SSO button widgets.
109 keys. splash_screen has no user-facing text (left untouched).
Established for batches B and C:
- `test/support/l10n_test_app.dart` — any test pumping a bare `MaterialApp`
  needs the delegates or `AppLocalizations.of` throws; supports pinning `es`.
- Canonical API values (chip options) keep their values and get translated
  labels only, via `ChoiceChipRow.labelBuilder` + a `_xLabel` switch helper.
- Strings assigned outside `build` (e.g. from `initState`) must become an enum
  or bool that `build` maps to copy — `context.l10n` is illegal there.
- Extraction was parallelized across agents writing `lib/l10n/_frag_*.json`
  fragments (no shared-ARB contention), verified English-verbatim against
  `git HEAD` before merging.

Per batch (A: auth/landing/settings/preferences/account · B: trips/itinerary/
today/budget/checklist · C: chat/alerts/share/export/remaining):

- [ ] Replace literals with `context.l10n.*`
- [ ] Add character-identical English entries to `app_en.arb`
- [ ] Add reviewed Spanish entries to `app_es.arb`
- [ ] Refactor strings built outside widget context (provider/service SnackBar
      messages) to keys rendered at the widget layer
- [ ] Layout spot-check under a temporary Spanish override (~25% expansion)
- [ ] `make flutter-analyze && make flutter-test` clean

- [ ] After PR 5: `untranslated-messages` output is empty

## PR 6 — Server-side Spanish + AI + providers

- [ ] Catalog entries for all server-rendered strings
- [ ] Email builders take a `locale` param: verification, reset, inline verify
      pages, invites, trip reminders, weekly nudges, price alerts
- [ ] Email jobs read `users.locale` (queries join the column)
- [ ] `trip_review.go` — findings, fix labels, localized dates
- [ ] `print_view_handler.go` + `share_preview_handler.go` — `<html lang>`,
      labels, `?lang=` param; `calendar_handler.go` — time-of-day labels
- [ ] `notifications_writer.go` — fallback actor string
- [ ] `plan_handler.go` — Spanish instruction appended only when locale != en
      (`basePrompt` and `plan_tool_registry.go` untouched)
- [ ] [P] Provider language params: `places_service.go`, `events_service.go`,
      `weather_service.go` (un-hardcode `language=en`)
- [ ] Tests: es email builders, Spanish trip-review integration test, and the
      **English prompt byte-stability** test via the fake-Anthropic harness
- [ ] `make smoke`

## PR 7 — Enablement

- [ ] `es` added to `supportedLocales` in `main.dart`
- [ ] Language picker in `account_settings_screen.dart`
      (System default / English / Español)
- [ ] Full Spanish walkthrough of every `spec.md` acceptance criterion via
      `make docker-dev`
- [ ] `make smoke`
