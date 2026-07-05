# Plan: Signup Onboarding Quiz

## Technical Approach

A nullable `users.onboarded_at` timestamp is the single source of truth: NULL
means the quiz is owed. The migration backfills existing users to `now()` so
only post-feature signups see the quiz. Clients get a computed
`needs_onboarding` bool on the auth user object, and the Flutter `AuthGate`
renders the quiz instead of the app shell while it's true — the same
declarative root-swap that already drives login/logout, so no imperative
navigation.

Quiz answers ride the **existing** `PUT /preferences` endpoint (keeping all
validation single-sourced in `preferences_handler.go`); completion is stamped
by a tiny idempotent `POST /auth/onboarding-complete` that returns the updated
user. Skip = stamp only. The two calls are deliberately not atomic — worst
case the quiz reappears and the re-save is an idempotent upsert; the prefs
save runs first so a stamp failure never loses answers.

Companions and trips-in-mind are formatted client-side into `profile_notes`
bullet lines matching the distiller convention (`- Travels with: …`,
`- Trips in mind: …`). No new columns and no AI call: `profile_notes` already
flows into the plan agent's system prompt, and `distillTravelerProfile` merges
(never wipes) notes, so quiz bullets survive later distillation. Replacing
notes wholesale is safe only because the quiz runs before the user could have
any — hence the spec's out-of-scope note about never reusing the screen later.

## Go API Changes

`src/packages/api/`:

- **Migration** `migrations/00023_onboarding.sql`: add `onboarded_at
  timestamptz` to `users`; backfill existing rows to `now()`.
- **Query** `query/users.sql`: `MarkUserOnboarded :one` — `SET onboarded_at =
  COALESCE(onboarded_at, now())` (idempotent, first-timestamp-preserving).
  Regenerate with `make api-sqlc`.
- **Handler** `auth_handler.go`: `UserResponse` gains `needs_onboarding`
  (computed `OnboardedAt == nil` in `toUserResponse` — propagates to
  register/login/me for free); new `completeOnboardingHandler`.
- **Routes** `main.go`: `POST /auth/onboarding-complete` behind
  `authMiddleware` + startup log line.

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **Model** `models/user.dart`: `needsOnboarding` (`@JsonKey(name:
  'needs_onboarding')`, constructor default `false` — tolerant of old API),
  then `make flutter-build-models`.
- **Service** `services/auth_service.dart`: `completeOnboarding(token)` →
  POST, returns the updated `UserModel`.
- **Provider** `providers/auth_provider.dart`:
  `AuthNotifier.completeOnboarding()` writes the returned user into state
  (this flips `AuthGate`). On any failure it unlocks locally anyway
  (`needsOnboarding: false` copy) so the user is never trapped; the quiz just
  reappears next session.
- **Widget** `widgets/choice_chip_row.dart`: `ChoiceChipRow` extracted from
  the private `_ChoiceRow` in `preferences_screen.dart`, shared by both
  screens.
- **Screen** `screens/onboarding_quiz_screen.dart`: five-step `PageView`
  (button-driven), global Skip in the `GradientAppBar`, `PageContainer` body,
  step dots, Back/Next/Finish footer. Pure `buildOnboardingProfileNotes()`
  builds the notes bullets (unit-tested). Finish saves via
  `preferencesProvider.notifier.save(...)` then stamps; a save failure shows a
  SnackBar and stays (Skip still available).
- **Gate** `main.dart` `AuthGate`: signed in && `needsOnboarding` →
  `OnboardingQuizScreen`, else `AppShell`.

## Contract Parity  ← anti-drift gate

| JSON key | Go type (`auth_handler.go`) | Dart type (`user.dart`) | Nullable? | ✓ |
|----------|-----------------------------|--------------------------|-----------|---|
| `needs_onboarding` | `bool` | `bool` (default `false`) | no | ☑ |

Quiz answers reuse the verified `/preferences` contract; re-confirmed the one
field the quiz newly writes:

| JSON key | Go type (`preferences_handler.go`) | Dart type (`traveler_preferences.dart`) | Nullable? | ✓ |
|----------|-------------------------------------|------------------------------------------|-----------|---|
| `profile_notes` | `*string` | `String?` | yes | ☑ |

## Cross-cutting

- **Env vars:** none.
- **Gateway:** new path is under `/api/v1/` — no proxy changes.
- **Rolling deploys:** old Flutter ignores the unknown `needs_onboarding` key;
  new Flutter against an old API defaults it to `false` (no quiz — current
  behavior). Safe both directions.

## Verification

- `make api-fmt && make api-vet` clean; `make flutter-build-models` then
  `make flutter-analyze` clean; `make flutter-test` passes.
- End-to-end via `make docker-dev` at `http://localhost:3000` (API container
  needs `up --build` for the migration):
  - Pre-feature user logs in → `needs_onboarding: false`, straight to the app.
  - `POST /auth/register` → 201 with `needs_onboarding: true`; UI shows the
    quiz; Finish → app shell; `GET /preferences` shows answers incl. notes
    bullets; the plan agent reflects them ("what do you know about me?").
  - Second user taps Skip → app shell, empty preferences, no quiz on relaunch.
  - `POST /auth/onboarding-complete` twice → 200 both, `onboarded_at`
    unchanged; unauthenticated → 401.
  - DB down mid-quiz → Skip still enters the app this session; quiz reappears
    next relaunch.
