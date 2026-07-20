# Plan: Spanish Localization (i18n)

> See `../../CLAUDE.md` for repo conventions referenced below.

## Technical Approach

Both packages are greenfield for i18n — there is no localization layer to
migrate around, and no locale is carried anywhere today. The shape of the
solution is therefore: **resolve the locale exactly once, on the client, and
carry it everywhere.**

Four decisions drive the rest:

1. **The client owns resolution.** Flutter computes an *effective locale*
   (explicit override, else device locale, else English) and sends it on every
   request as `Accept-Language`. The server never re-derives it and never reads
   the DB to find it. One resolution point means the override cannot disagree
   with the header.
2. **The stored locale lives on `users`, not `traveler_preferences`.** Locale
   is app configuration, not travel taste. The background email jobs
   (`reengagement_checker.go`, `price_alert_checker.go`) run with no request and
   already read the users row, so a column there is free to join; a
   `traveler_preferences` column would add a LEFT JOIN to every one of them
   *and* would put locale inside the AI's `save_preferences` tool, which must
   not be able to change it. This mirrors `00044_email_prefs.sql`.
   The stored value is used **only** where there is no request: background
   email, and token-gated exports.
3. **Localize what users read, not what developers read.** Emails, trip-review
   findings, export pages and `.ics` labels go through a catalog. The ~hundreds
   of `writeJSONError` strings do not (see spec → Out of Scope).
4. **The English path stays byte-identical.** Every server-side change is gated
   on `locale != "en"`, and the AI system prompt in particular is only appended
   to for non-English requests — so English prompt-cache behavior and English
   output are provably unchanged. This is the single most important invariant
   in the feature and has a dedicated regression test.

Sequencing: the Flutter string extraction is ~800 literals, so `es` is **not**
added to `supportedLocales` until the very last PR. Every extraction PR is
therefore behavior-neutral and independently shippable, and the risky enablement
is one small, revertable change.

## Go API Changes

`src/packages/api/` (all `package main`):

- **`i18n.go`** (new) — the whole locale layer:
  - `supportedLocales` / `languageNames` — the source of truth; adding a locale
    is an append here plus catalog entries.
  - `normalizeLocale` — base-subtag folding (`es-MX` → `es`), used by both
    negotiation and the PATCH validator.
  - `matchLocale` — `Accept-Language` parsing, q-value ordered.
  - `localeMiddleware` + `requestLocale(ctx)` — stamps and reads the negotiated
    locale; `requestLocale` returns `en` outside a request, so every call site
    is safe by default.
  - `tr(locale, key, args...)` — catalog lookup with `locale → en → key`
    fallback and `Sprintf` templating.
  - `localizedDate(locale, t, style)` — Go's `time.Format` emits English month
    and weekday names unconditionally, so localized dates need their own tables.
- **Middleware registration:** `router.Use(localeMiddleware)` in `main.go`,
  after `corsMiddleware` (it must run for every route, including the public
  export routes).
- **Migration** `migrations/00049_user_locale.sql` — `users.locale TEXT` (NULL =
  never resolved). Down drops it.
- **Queries** `query/users.sql` — `UpdateUserProfile` replaces the
  display-name-only setter with the partial-update `COALESCE(sqlc.narg(...))`
  pattern already used by `SetUserEmailOptOut`, so one query updates display
  name and/or locale. Regenerate with `make api-sqlc`; never hand-edit `store/`.
- **Handlers:** `patchAccountHandler` (`account_handler.go`) accepts an optional
  validated `locale`; `UserResponse`/`toUserResponse` (`auth_handler.go`) expose
  it, so `/auth/me` and every auth response carry it.

Later PRs (see below) thread `requestLocale(ctx)` into `trip_review.go`, the
email builders, `print_view_handler.go`, `share_preview_handler.go`,
`calendar_handler.go`, `plan_handler.go`, and the provider query strings in
`places_service.go`, `events_service.go` and `weather_service.go`.

### Prompt-cache constraint (CLAUDE.md → Key Constraints)

`plan_tool_registry.go` is **not touched**: no `language` field is added to
`save_preferences`, so the registry stays byte-stable. `basePrompt` is not
touched either. The Spanish instruction is appended to the assembled
`systemPrompt` in `plan_handler.go` only when the locale is non-English. The
cache breakpoint covers the whole system block and the prompt already varies per
user and per day, so a per-locale cache line is free; English is unchanged.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **Localization**: `flutter_localizations` + `intl` in `pubspec.yaml` with
  `generate: true`; `l10n.yaml`; `lib/l10n/app_en.arb` + `app_es.arb`;
  `lib/l10n/l10n.dart` exposing a `context.l10n` extension so call sites stay
  short. `untranslated-messages-file` makes missing Spanish a build artifact
  that CI can assert on.
- **Provider** `providers/locale_provider.dart` — persists the override in
  `shared_preferences` (pattern: `providers/recent_trip_provider.dart`), exposes
  the effective locale, and on change sets `Intl.defaultLocale`, updates the
  API client's language tag, and fire-and-forgets the account sync (pattern:
  `providers/preferences_provider.dart`).
- **Client** `services/api_client.dart` — `Accept-Language` in `jsonHeaders()`,
  next to the existing bearer-token injection.
- **App shell** `main.dart` — `localizationsDelegates`, `supportedLocales`,
  `locale`. `GlobalMaterialLocalizations.delegate` also initializes `intl` date
  symbols, so no manual `initializeDateFormatting` is needed.
- **Models** — the auth user model gains `locale`; run
  `make flutter-build-models`.
- **Formatting** `utils/trip_format.dart` and `utils/money_format.dart` — the
  hand-rolled English month table becomes `DateFormat`, and money digits get
  `NumberFormat` grouping. Both keep their current signatures, so their ~10 call
  sites are untouched. Currency *symbol* selection stays currency-driven (it is
  not a locale concern).
- **Screens/widgets** — literals become `context.l10n.*` across
  `screens/` and `widgets/`.
- **Settings** `screens/account_settings_screen.dart` — a *Language / Idioma*
  section using the existing `SectionHeader` pattern.

## Contract Parity

| JSON key | Go type (`auth_handler.go`) | Dart type (`models/`) | Nullable? | ✓ |
|----------|-----------------------------|-----------------------|-----------|---|
| `locale` | `*string` (`omitempty`) | `String?` | yes | ☐ |

`users.locale` is nullable (never-resolved accounts), so the Go field is a
pointer and the Dart field is nullable.

## Cross-cutting

- **Env vars:** none. Locale is per-user data, not configuration.
- **Gateway:** no new paths; `Accept-Language` is a standard header and passes
  through the nginx proxy untouched.
- **Migrations:** `00049` follows `00048_apple_sso.sql`.

## PR sequence

| PR | Content |
|----|---------|
| 1 | This spec + server locale foundation: migration, `i18n.go`, account PATCH/`/auth/me`, middleware |
| 2 | Flutter i18n infrastructure (invisible: `supportedLocales` is `[en]` only) + `locale_provider` + `Accept-Language` + intl date/money |
| 3 | String extraction A — auth, landing, settings, preferences, account |
| 4 | String extraction B — trips, itinerary, today mode, budget, checklist |
| 5 | String extraction C — chat/plan, alerts, share/export, remaining widgets and non-`Text` strings |
| 6 | Server-side Spanish (emails, trip review, exports, `.ics`) + AI language instruction + provider language params — all ships dark |
| 7 | Enablement: `es` in `supportedLocales`, the settings picker, end-to-end pass |

## Verification

- `make api-fmt && make api-vet` clean.
- `make api-test`; Go unit tests for `matchLocale` (q-values, regional variants,
  unsupported), `tr` fallback, `localizedDate`, and a catalog-completeness test
  that fails if any key lacks a translation.
- Integration tests (`TEST_DATABASE_URL`, `travel_planner_test`): account locale
  round-trips through PATCH and `/auth/me`; an invalid locale is rejected; a
  Spanish `Accept-Language` produces Spanish trip-review findings (PR 6).
- **English byte-stability regression test** (PR 6) via the fake-Anthropic
  harness (`ANTHROPIC_BASE_URL`): the system prompt received for an English
  request is unchanged, and the Spanish instruction appears only under `es`.
- `make flutter-build-models`, `make flutter-analyze`, `make flutter-test`;
  a widget test pumping the app under `es`; per-extraction-PR layout spot-check
  with a temporary Spanish override (text expansion).
- Manual end-to-end via `make docker-dev` at `http://localhost:3000`: switch to
  Español and walk every acceptance criterion — chat, trip health, print packet,
  `.ics`, and a triggered verification email.
- `make smoke` after PRs 6 and 7.
