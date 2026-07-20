# Tasks: Sign in with Apple

> Dependency-ordered; built in one pass on branch apple-sso.

## Persistence

- [x] Migration `00048_apple_sso.sql`: provider CHECK → `('google','apple')`;
      down deletes only stranded Apple-only accounts
- [x] No sqlc changes (queries already provider-parameterized); `resetDB`
      already truncates `auth_identities`

## API (Go)

- [x] `apple_oauth.go` — env getters, URL seams, ES256 client-secret JWT
      (raw r||s), `flexBool`, `exchangeAppleCode` (no PKCE),
      `parseAppleIDToken`, `parseAppleUserField`
- [x] `apple_auth_handler.go` — availability / start (SameSite=None Secure
      state cookie, form_post redirect) / POST callback /
      `findOrCreateAppleUser` (name-once capture, relay-email friendly)
- [x] `googleExchangeHandler` → `ssoExchangeHandler`; `/auth/sso/exchange` +
      `/auth/google/exchange` alias; Apple routes registered (strict tier) +
      startup log line
- [x] Env samples: `src/packages/api/.env.sample`,
      `dockerize/production/.env.sample` (four `APPLE_*` vars)

## Tests (Go)

- [x] `fake_apple_test.go` — in-test P-256 key; token endpoint verifies the
      client-secret JWT with `ecdsa.Verify` and rejects `code_verifier`
- [x] `apple_auth_integration_test.go` — 13 cases: availability, 503,
      redirect contents (form_post, no PKCE, None+Secure cookie), state
      mismatch, declined, happy path + name capture, repeat without `user`
      field, auto-link, unverified/missing email refusal, string bools,
      private relay, exchange single-use + alias, client-secret unit test

## UI (Flutter)

- [x] `appleSignInAvailable` + `exchangeSsoCode` → `/auth/sso/exchange`
- [x] `appleSsoAvailableProvider`
- [x] `sso_buttons.dart` (shared divider), slimmed
      `google_sign_in_button.dart`, new `apple_sign_in_button.dart`
      (`Icons.apple`, HIG black) — wired into `auth_screen.dart`
- [x] `sso_callback_screen.dart` wording made provider-neutral

## Tests (Flutter)

- [x] `sso_buttons_test.dart` (4 availability combinations, single divider)
- [x] `apple_sign_in_button_test.dart`, updated google/sso-callback tests

## Verification

- [x] Full Go suite green (Postgres test DB); Google suite unaffected by the
      exchange rename
- [x] `flutter analyze` clean + full widget suite green
- [ ] Post-enrollment prod smoke (plan.md runbook step 7) — blocked on Apple
      Developer Program enrollment
