# Plan: Invite Co-Planners by Email

> **HOW.** See `../../CLAUDE.md` for repo conventions.

## Technical Approach

A dedicated `trip_invites` table (00036) rather than reusing `email_tokens`
(requires a user_id — invitees may have no account) or `trip_shares`
(anonymous multi-use links, no address binding or per-invite revoke). Tokens
are minted with `generateSessionToken()` and stored as sha256 via the
existing `hashEmailToken`; emails go through `EmailService.Send`
fire-and-forget. Redemption reuses the collaborative-editing machinery:
accept = `AcceptTripInvite` (race-safe conditional update) +
`CreateTripCollaborator` in one transaction. The public preview returns the
exact `SharedTripResponse` shape by extracting `buildSharedTripResponse` from
`sharedTripHandler`, so Flutter reuses `SharedTripScreen` with a `linkKind`
switch.

## Go API Changes

- `migrations/00036_trip_invites.sql` — table + partial unique index
  (one live invite per lineage+email) + owner/chat index.
- `query/invites.sql` — Create/ListPending/RevokeByEmail/RevokeByID/
  GetValidByTokenHash/GetByTokenHash/Accept/CountPending; `make api-sqlc`.
- `invite_handler.go` — create (owner-only, normalize + `validateEmail`,
  self-invite 422, `shareChatID` for legacy trips, 20-pending cap,
  revoke-then-mint reissue, `sendInviteEmail` goroutine), list, revoke,
  public preview (`resolveInvite`, mirrors `resolveShare` 404 posture),
  accept (idempotent re-accept, owner no-op that leaves the token live).
  Analytics: `invite_sent` / `invite_accepted` / `invite_revoked`.
- `share_handler.go` — extract `buildSharedTripResponse` (chat_id stripped,
  no booking todos) shared by both token preview paths.
- Routes in `main.go` beside the share/collaborator block; create + accept on
  `strict(...)`, preview public like `/shared/{token}`.

## Flutter Changes

- `services/trips_api_service.dart`: `createInvite` (surfaces server error
  text), `listInvites`, `revokeInvite`, `getInvitedTrip`, `acceptInvite`.
- `trip_detail_screen.dart` `_CoPlannersSheet`: email `TextField` + Invite
  button, parallel load of collaborators + pending invites, pending rows
  with revoke, keyboard-aware padding, `onInvited` snackbar. Share-menu item
  renamed "Copy invite link (can edit)".
- `providers/shared_trip_provider.dart`: `invitedTripProvider` family.
- `screens/shared_trip_screen.dart`: `SharedLinkKind {share, invite}`
  threaded through screen + body; join calls `acceptInvite` for invites;
  save-a-copy hidden on invite links; invite-specific dead-link copy.
- `main.dart`: `invite/{token}` deep-link route (same pattern as
  `share/{token}`).

## Contract Parity  ← anti-drift gate

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| invite `id`/`email`/`role` | `string` | `String` | no | ✓ |
| invite `created_at`/`expires_at` | `time.Time` | `DateTime` (parsed) | no | ✓ |
| preview payload | `SharedTripResponse` | `SharedTrip` (existing) | — | ✓ |
| accept `trip_id`/`access` | `string` | `String` | no | ✓ |

## Cross-cutting

- Email links use the existing `PUBLIC_BASE_URL`/`PUBLIC_APP_PATH` env vars
  (no new vars). Degraded SMTP logs bodies — dev flow works without config.

## Verification

- `invite_integration_test.go` (known-token rows inserted via store since
  only hashes persist): create/list/revoke + non-owner 404s + normalization
  + self-invite 422 + legacy chat_id assignment; accept grants editable
  membership + consumes the token (idempotent for redeemer, 404 for others,
  email-mismatch redemption allowed, accepted_by recorded); expired/revoked/
  unknown all 404; re-invite voids the old token; owner self-open no-op.
- Full Go suite; `flutter analyze` + `flutter test`.
- Manual: invite flow end-to-end with degraded-SMTP logged link, including
  the signed-out → sign-up → accept path.
