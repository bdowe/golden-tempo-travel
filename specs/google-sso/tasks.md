# Tasks: Sign in with Google

> Dependency-ordered; all complete (built in one pass on branch google-sso).

## Persistence

- [x] Migration `00032_google_sso.sql`: `auth_identities` table, nullable
      `users.password_hash`, `email_tokens` purpose CHECK widened to `sso`
- [x] `query/auth_identities.sql` (Get/Create) + `make api-sqlc`
- [x] Fix the four `password_hash` call sites for `*string`
      (`hasPassword`/`checkUserPassword` helpers in `auth_service.go`)

## API (Go)

- [x] `google_oauth.go` — PKCE helpers, token exchange, claim validation,
      env config + URL test seams
- [x] `google_auth_handler.go` — start (302 + state cookie), callback
      (linking rules → one-time code → 303), exchange (code → session),
      availability
- [x] Register the four routes in `main.go` (strict tier for the flow routes)
- [x] Env samples: `src/packages/api/.env.sample`,
      `dockerize/production/.env.sample`

## Tests (Go)

- [x] `fake_google_test.go` — fake token endpoint minting unsigned id_tokens
- [x] `google_auth_integration_test.go` — 11 cases: availability, start
      redirect, state mismatch, declined consent, happy path, repeat sub,
      email auto-link, unverified-email refusal, single-use code, SSO-only
      account policies
- [x] `auth_identities` added to the `resetDB` TRUNCATE list

## UI (Flutter)

- [x] `googleSignInAvailable` + `exchangeSsoCode` in `services/auth_service.dart`
- [x] `googleSsoAvailableProvider` in `providers/auth_provider.dart`
- [x] `widgets/google_sign_in_button.dart` (availability-gated; same-tab
      launch) + wired into `screens/auth_screen.dart`
- [x] `screens/sso_callback_screen.dart` + `/sso/<code>` route in `main.dart`
- [x] Official G logo asset `assets/images/google_g_logo.png`

## Tests (Flutter)

- [x] `test/google_sign_in_button_test.dart` — hidden/visible by availability
- [x] `test/sso_callback_screen_test.dart` — exchange+adopt+navigate, error
      code, expired code

## Verification

- [x] Full Go suite green against a Postgres test DB
- [x] `flutter analyze` clean (no new issues) + widget tests green
- [x] Manual click-through with real Google credentials — verified on
      production (goldentempotravel.com) 2026-07-20; consent screen published
