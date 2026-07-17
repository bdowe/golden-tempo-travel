# Spec: Invite Co-Planners by Email

## Context

Sharing a trip with a friend today means minting a link and pasting it into
some other app. That works, but it's clunky as the primary flow and the link
is a bearer capability that never expires until sharing is turned off
entirely. This feature makes "type your friend's email" the first-class way
to invite a co-planner: the friend gets an email with a single-use, one-week
link that previews the trip and joins them as an editor — whether or not they
have an account yet.

## User Stories

- As a **trip owner**, I want **to invite a friend by email from the app** so
  that **I don't have to copy links into another messenger**.
- As an **invited friend without an account**, I want **the emailed link to
  show me the trip and walk me through sign-up and joining** so that **the
  first-run experience is one continuous flow**.
- As a **trip owner**, I want **to see and revoke pending invites** so that
  **a mis-typed address or changed mind is recoverable**.

## Acceptance Criteria

- [ ] The Manage co-planners sheet has an email field; submitting it sends an
      invite email and shows the address under "Pending invites" with its
      expiry and a revoke control.
- [ ] The emailed link opens a read-only preview of the trip (no account
      needed) with a "Join as co-planner" action that routes through
      sign-in/sign-up when necessary and lands in the shared trip.
- [ ] An invite works exactly once and expires after 7 days; revoked,
      expired, used, and unknown tokens are indistinguishable to a visitor.
- [ ] Re-inviting the same address voids the earlier link and sends a fresh
      one; at most one live invite exists per (trip, address).
- [ ] The redeemer's account email does not have to match the invited
      address (SSO reality) — the invite records who actually joined.
- [ ] Creating an invite reveals nothing about whether the address has an
      account, and the response never contains the token.
- [ ] Only the trip owner can create, list, or revoke invites (non-owners get
      not-found).
- [ ] Inviting yourself is rejected; a live-invite cap per trip prevents
      email-spray abuse; create/accept sit on the strict rate tier.

## API Surface

### `POST /api/v1/trips/{id}/invites` (owner, strict tier)
- **Request:** `{ "email": "friend@example.com" }` — trimmed and lowercased.
- **Response:** 201 with the invite record (id, email, role, created_at,
  expires_at). Never the token. Identical whether or not the email has an
  account.
- **Errors:** 400 invalid email; 422 self-invite or pending-cap reached; 404
  non-owner/unknown trip.

### `GET /api/v1/trips/{id}/invites` (owner)
- Pending invites for the trip's lineage (empty for never-shared legacy
  trips).

### `DELETE /api/v1/trips/{id}/invites/{inviteId}` (owner)
- Voids one pending invite; 404 if unknown, dead, or not the owner's.

### `GET /api/v1/invites/{token}` (public)
- Same stripped shape as `GET /shared/{token}` (owner name, role, no
  chat_id, no booking todos); 404 posture for any dead token.

### `POST /api/v1/invites/{token}/accept` (auth, strict tier)
- Redeems into editor membership; returns `{trip_id, access}`. Single-use and
  race-safe; idempotent for the user who already redeemed; owner opening
  their own invite is a no-op success that leaves the token live.

## Data Model

- **Trip invite** — one emailed invitation to co-plan a trip lineage: the
  invited address, the role, the token's hash (plaintext transits email
  only), an expiry, and lifecycle timestamps (accepted — with who actually
  redeemed —, revoked). At most one live invite per (lineage, address).

## UI Behavior

- **Manage co-planners sheet:** email field + Invite button on top; active
  co-planners; "Pending invites" rows (mail icon, "Invited — expires in Nd",
  revoke). Snackbar "Invite sent to {email}". Errors surface inline in the
  sheet.
- **Share menu:** the link-copy item is renamed "Copy invite link (can
  edit)" to disambiguate from email invites.
- **Invite deep link (`/invite/{token}`):** reuses the shared-trip screen —
  preview, then "Join as co-planner" through the existing sign-in flow. No
  save-a-copy on invite links (they are join capabilities, not browse
  links). Dead-link state explains the invite may have expired, been
  revoked, or already used.

## Edge Cases & Error States

- SMTP unconfigured (dev): the email body is logged; the API still returns
  201.
- Two people racing the same token: exactly one wins; the loser sees the
  dead-link state.
- Invitee already a collaborator: accept is harmlessly idempotent
  (membership insert is a no-op).
- Legacy trips without a lineage get one assigned on first invite.

## Out of Scope

- Viewer-role email invites (schema carries `role` for later).
- An in-app "invites waiting for you" surface — redemption is purely via the
  emailed link.
- Requiring a verified email to accept (parity with link joins).

## Open Questions

None — resolved during planning: token-is-the-capability (no email-match
enforcement), 7-day TTL, editor-only v1.
