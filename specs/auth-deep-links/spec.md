# Spec: Reset & Verify Email Deep Links

> **WHAT & WHY only.**

## Context

Email auth shipped with a paste-a-code password reset (two dialogs on the sign-in
screen) and a verification link that lands on a bare API-rendered HTML page. Both
work, but neither takes the user *into the app*. This feature adds app deep links
to the emails — `/reset/<token>` and `/verify/<token>` — so tapping the email link
opens a proper in-app screen that completes the action. The existing code-paste
dialogs and the API's HTML verify endpoint are kept so older emails and manual
fallback still work.

## User Stories

- As a **user who forgot my password**, I want the reset email's link to open a
  form in the app so that I can set a new password without copying a code.
- As a **new user**, I want the verification email's link to open the app and
  confirm my address with a clear success message so that I know it worked.
- As an **operator**, I want the emailed links to respect where the app is
  publicly served (base URL and path prefix) so links work in every deployment.

## Acceptance Criteria

- [ ] Opening `/reset/<token>` shows a standalone screen with new-password +
      confirm fields; passwords must be at least 8 characters and match.
- [ ] Submitting a valid token updates the password, shows "Password updated",
      and a "Sign in" button returns to the app root; an invalid/expired token
      shows the server's error inline without leaving the screen.
- [ ] Opening `/verify/<token>` verifies the email automatically, showing a
      spinner, then "Email verified ✓" on success or "Link expired or already
      used" on failure, with a "Continue" button to the app root.
- [ ] The password-reset email leads with the `/reset/<token>` app link and
      still includes the paste-able code as a fallback.
- [ ] The verification email's primary link is the `/verify/<token>` app route
      and states it expires in 24 hours; the old API GET verify link keeps
      working for previously sent emails.
- [ ] Email links honor the configured public base URL and an optional app
      path prefix (default `/`).

## API Surface

No new endpoints. The existing `POST /api/v1/auth/verify-email` (JSON `{token}`)
and `POST /api/v1/auth/reset-password` are consumed by the new screens; the
`GET /api/v1/auth/verify-email?token=` HTML page is unchanged.

## Data Model

No changes.

## Out of Scope

- URL strategy (hash vs path) — the routes work under either; clean path URLs
  ship separately.
- Auto sign-in after reset or verify.
