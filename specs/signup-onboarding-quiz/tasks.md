# Tasks: Signup Onboarding Quiz

> Dependency-ordered. `[P]` = can run in parallel with its siblings (no shared
> files / no ordering dependency). Work top to bottom; verification is last.

## API (Go)

- [x] Migration `00023_onboarding.sql`: `users.onboarded_at timestamptz`,
      backfill existing rows to `now()`
- [x] `query/users.sql`: `MarkUserOnboarded :one` (COALESCE keeps first stamp)
- [x] `make api-sqlc` — `store.User.OnboardedAt`, `MarkUserOnboarded` generated
- [x] `auth_handler.go`: `UserResponse.NeedsOnboarding` + `toUserResponse` +
      `completeOnboardingHandler`
- [x] `main.go`: route `POST /auth/onboarding-complete` (auth) + log line

## Models & codegen (Flutter)

- [x] `models/user.dart`: `needsOnboarding` field (default `false`)
- [x] Run `make flutter-build-models` to regenerate `user.g.dart`
- [x] Complete the Contract Parity table in `plan.md` (every row ✓)

## UI (Flutter)

- [x] [P] `services/auth_service.dart`: `completeOnboarding(token)`
- [x] [P] `providers/auth_provider.dart`: `completeOnboarding()` with local
      unlock fallback
- [x] Extract `widgets/choice_chip_row.dart` from `preferences_screen.dart`
- [x] Build `screens/onboarding_quiz_screen.dart` (5 steps, Skip, submit,
      loading/error states, `buildOnboardingProfileNotes`)
- [x] Wire `AuthGate` in `main.dart`

## Tests

- [x] Unit-test `buildOnboardingProfileNotes` (`test/onboarding_quiz_test.dart`)
- [x] Widget test: `AuthGate` shows quiz when `needsOnboarding: true`

## Verification

- [x] `make api-fmt && make api-vet` clean
- [x] `make flutter-analyze` clean
- [x] `make flutter-test` / `make api-test` pass (as applicable)
- [x] Manual end-to-end via gateway (`make docker-dev` → `http://localhost:3000`):
      every acceptance criterion in `spec.md` checked off
