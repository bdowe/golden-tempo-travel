# Spec: Signup Onboarding Quiz

## Context

New users land in the app with an empty traveler profile — the planning agent
only learns about them slowly through conversation. A short, skippable quiz
shown once right after signup seeds the travel profile (budget, pace,
interests, home airport, who they travel with, and trips they're dreaming
about) so the very first planned trip is already personalized.

## User Stories

- As a **new user**, I want to answer a few quick questions right after signing
  up so that my first planning session already reflects my travel style.
- As a **new user in a hurry**, I want to skip the quiz instantly so that I can
  get into the app, without being nagged about it again.
- As an **existing user**, I never want to see the quiz — my account predates
  it.
- As **any user**, I want to complete or change my answers later from the
  account menu's Travel profile screen.

## Acceptance Criteria

- [x] Immediately after signup, the quiz appears (before the main app); a Skip
      control is visible on every step.
- [x] Skipping lands the user in the app with nothing saved; the quiz does not
      reappear on the next sign-in.
- [x] Completing the quiz lands the user in the app; the answers appear in the
      Travel profile screen and in the preferences API.
- [x] The trips-in-mind text and travel-companions answer influence the
      planning agent (visible in its personalization). *(Verified that the
      bullets land in `profile_notes`, which the agent's system prompt already
      injects; no live agent call was made.)*
- [x] Users created before this feature never see the quiz — existing accounts
      sign in straight to the app.
- [x] Every question is optional; Next always proceeds.
- [x] If saving answers fails, the user is informed and is never trapped in
      the quiz (Skip still works). *(Covered by code paths — error SnackBar +
      local-unlock fallback — not exercised end-to-end.)*
- [x] Signing out mid-quiz returns to the landing page; the quiz reappears on
      the next sign-in until completed or skipped.

## API Surface

### Auth user object (register / login / me)
- Gains a **`needs_onboarding`** boolean: true until the user completes or
  skips the quiz. Accounts that existed before this feature report false.

### `POST /api/v1/auth/onboarding-complete`
- **Purpose:** mark the signed-in user as having finished (or skipped)
  onboarding.
- **Request:** no body. Requires authentication.
- **Response:** the updated user object (`needs_onboarding: false`).
- **Errors:** 401 when not authenticated; 503 when persistence is unavailable.
- **Idempotent:** repeated calls succeed and keep the original completion time.

Quiz answers themselves travel over the **existing preferences contract**
(`PUT /api/v1/preferences`) — no new fields there.

## Data Model

- **User** — gains a record of *when* onboarding was completed; absent means
  the quiz is still owed. Pre-existing users are backfilled as already
  onboarded.
- **Traveler preferences** — unchanged. Travel companions and trips-in-mind are
  stored as bullet lines inside the existing free-form profile notes, which the
  planning agent already reads and maintains.

## UI Behavior

- **Surface:** a full-screen, five-step quiz rendered instead of the main app
  whenever a signed-in user still owes onboarding (fresh signup, or app
  relaunch before completing/skipping).
- **Steps:** 1. travel style (budget + pace), 2. interests, 3. travel
  companions, 4. home airport, 5. trips you're dreaming about (free text) with
  a Finish button.
- **Happy path:** answer any subset → Finish → answers saved → main app.
- **Skip:** always visible in the header; saves nothing and enters the app.
- **States:** Next/Finish shows a spinner while saving; a save failure shows an
  error message and stays on the quiz (Skip remains available).

## Edge Cases & Error States

- All questions unanswered + Finish → nothing meaningful saved; user enters
  the app; quiz never reappears.
- Persistence down when skipping/finishing → the user still enters the app for
  this session; the quiz reappears next session (completion never persisted).
- Free-text answer is length-capped; overlong input is truncated safely.
- Sign-out mid-quiz → landing page; quiz state is not persisted.

## Out of Scope

- Conversational / AI-interview onboarding.
- Creating draft trips from the trips-in-mind answer.
- A dedicated "retake quiz" menu entry (the Travel profile screen covers later
  edits). The quiz screen must not be reused in contexts where the user may
  already have agent-maintained profile notes.
- Re-showing the quiz when preferences change or are cleared.

## Open Questions

None — format (structured multi-step), gating (skippable, shown once), and
trip-ideas handling (profile only) were resolved with the product owner before
implementation.
