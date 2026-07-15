# Spec: Sign in with Google

> **WHAT & WHY only.** Implementation details live in `plan.md`.

## Context

Account creation is email + password only, which adds friction at the exact
moment a visitor decides to try the product. A "Continue with Google" option
removes the password ceremony for the majority of travelers, verifies the
email address for free, and reduces abandoned signups. The original
user-accounts spec explicitly deferred social login; this feature closes that
gap for the web product. Scope: Google only, web only — native-mobile SSO and
other providers remain out of scope.

## User Stories

- As a **new visitor**, I want to create an account with one Google click so
  that I don't have to invent and remember another password.
- As an **existing email+password user**, I want signing in with Google (same
  address) to land me in my existing account, not a duplicate one.
- As a **returning Google user**, I want the button to sign me straight in on
  any browser.

## Acceptance Criteria

- [ ] The sign-in/sign-up screen shows a "Continue with Google" button when
      (and only when) the server has Google sign-in configured.
- [ ] Clicking it walks through Google's consent screen and lands the user in
      the app, signed in, without ever entering a password.
- [ ] A first-time Google user gets a new account (display name from their
      Google profile, email pre-verified) and sees the onboarding quiz, same
      as an email signup.
- [ ] A Google sign-in whose (verified) email matches an existing account
      signs into that account and links it — no duplicate account, and the
      original password keeps working.
- [ ] A Google account with an **unverified** email is refused (no link, no
      sign-in) — this is the account-takeover guard.
- [ ] Repeating Google sign-in with the same Google account always lands in
      the same app account.
- [ ] Declining the consent screen, tampering with the redirect, or reusing an
      expired handoff link shows a friendly error with a path back to sign-in
      — never a raw error page.
- [ ] SSO-only accounts (no password set): password login fails with the
      generic credentials error; "change password" explains how to set one via
      the forgot-password flow; account deletion works on the session alone.
- [ ] With no Google credentials configured on the server, the button is
      absent and email+password auth is completely unaffected.

## API Surface

### `GET /api/v1/auth/google/availability`
- **Purpose:** lets the app decide whether to render the Google button.
- **Response:** `{available: bool}` — true only when the server has an OAuth
  client configured and a database.

### `GET /api/v1/auth/google`
- **Purpose:** starts the redirect flow; the browser navigates here directly.
- **Response:** redirect to Google's consent screen. 503 when unconfigured.

### `GET /api/v1/auth/google/callback`
- **Purpose:** Google redirects back here after consent.
- **Response:** redirect to the app at `/sso/<one-time code>` on success, or
  `/sso/error` on any failure (declined, tampered state, unverified email).
  Always a redirect — this is a top-level browser navigation.

### `POST /api/v1/auth/google/exchange`
- **Purpose:** the app swaps the one-time code for a real session.
- **Request:** `{code}` from the `/sso/<code>` URL.
- **Response:** identical to login: `{user, token}`.
- **Errors:** 404 for an invalid, expired (60s), or already-used code.

## Data Model

- **Auth identity** — a link between an app user and an external provider
  identity (`google` + Google's stable subject id). One Google account maps to
  at most one app user. Deleting the user deletes the link.
- **User** — the password becomes optional; an account may be SSO-only.
  Google-created accounts are email-verified from birth.
- **Handoff code** — reuses the existing single-use email-token machinery with
  a new `sso` purpose and a 60-second lifetime.

## Non-Goals

- Native mobile SSO (Google/Apple plugins, per-platform config).
- Other providers (Apple, GitHub, …) — the identity table is provider-keyed
  so adding one later is additive.
- A "connected accounts" section in account settings (viewing/unlinking).
- Letting SSO-only users set a password anywhere other than the existing
  forgot-password flow.
