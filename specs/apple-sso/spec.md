# Spec: Sign in with Apple

> **WHAT & WHY only.** Implementation details live in `plan.md`.

## Context

Google sign-in removed the password ceremony for most travelers; Apple users
— especially anyone arriving on an iPhone or iPad — expect the same one-tap
option, and Apple's Hide-My-Email appeals to privacy-conscious users. The
identity machinery built for Google (external identities, one-time handoff
codes, SSO-only accounts) is provider-agnostic, so Apple is a small delta.
**This feature ships dark**: it requires Apple Developer Program enrollment
(not yet done), so until credentials are configured the button is hidden and
nothing changes for any user.

## User Stories

- As an **Apple-ecosystem visitor**, I want to create an account with my
  Apple ID so that I don't need another password.
- As a **privacy-conscious user**, I want to sign up with Hide My Email and
  still get a working account.
- As an **existing user**, I want signing in with Apple (same address) to
  land me in my existing account, not a duplicate.

## Acceptance Criteria

- [ ] The sign-in screen shows "Continue with Apple" only when the server has
      Apple credentials configured; with Google also configured, both buttons
      share a single "or" divider.
- [ ] Clicking it walks through Apple's consent sheet and lands the user in
      the app signed in, without a password.
- [ ] A first-time Apple user gets a new account using the name they shared
      on the consent sheet (Apple sends it only that once), email
      pre-verified, and sees the onboarding quiz.
- [ ] Repeat Apple sign-ins land in the same account and keep that name.
- [ ] A Hide-My-Email (private relay) signup creates a working account under
      the relay address.
- [ ] An Apple sign-in whose verified email matches an existing account signs
      into and links that account — no duplicate; the original password keeps
      working.
- [ ] An unverified or missing Apple email is refused (takeover guard).
- [ ] Cancelling the consent sheet, tampering with the redirect, or reusing
      an expired handoff link shows the friendly error screen.
- [ ] SSO-only accounts behave exactly as Google's: generic 401 on password
      login, guided message on change-password, session-only deletion.
- [ ] With no Apple credentials configured, the button is absent and all
      existing auth (email+password, Google) is completely unaffected.

## API Surface

### `GET /api/v1/auth/apple/availability`
- **Response:** `{available: bool}` — true only with full Apple credentials
  and a database.

### `GET /api/v1/auth/apple`
- **Purpose:** starts the redirect flow. 503 when unconfigured.

### `POST /api/v1/auth/apple/callback`
- **Purpose:** Apple posts the result here (a cross-site form POST — unlike
  Google's GET callback). Redirects to `/sso/<one-time code>` on success or
  `/sso/error` on any failure.

### `POST /api/v1/auth/sso/exchange`
- **Purpose:** provider-neutral swap of the one-time code for a session
  (`{user, token}`, identical to login). `/auth/google/exchange` remains as
  an alias. 404 for invalid/expired/used codes.

## Data Model

- **Auth identity** — the existing table now accepts provider `apple`.
- Everything else (handoff codes, SSO-only users) is reused unchanged.

## Non-Goals

- Native iOS/macOS Sign in with Apple (the ASAuthorization plugin flow).
- ID-token signature verification against Apple's JWKS (same server-to-server
  trust decision as Google; revisit if tokens ever arrive via a browser).
- A "connected accounts" management UI / unlinking.
- Registering the outbound-email domain with Apple's private relay is an ops
  task (documented in plan.md), not part of this change.
