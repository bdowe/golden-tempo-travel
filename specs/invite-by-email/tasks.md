# Tasks: Invite Co-Planners by Email

> Dependency-ordered. Work top to bottom; verification is last.

## API (Go)

- [x] Migration 00036 `trip_invites` (+ partial unique pending index)
- [x] `query/invites.sql` + `make api-sqlc`
- [x] Extract `buildSharedTripResponse` from `sharedTripHandler`
- [x] `invite_handler.go` (create/list/revoke/preview/accept +
      `sendInviteEmail`) + routes (strict on create/accept)
- [x] Analytics events

## UI (Flutter)

- [x] Service methods (create/list/revoke/getInvitedTrip/accept)
- [x] `_CoPlannersSheet` email input + pending-invites section
- [x] `invite/{token}` deep link; `SharedTripScreen` linkKind param
- [x] Share-menu rename to "Copy invite link (can edit)"

## Verification

- [x] `go vet` + full `go test` (5 new integration test funcs)
- [x] `flutter analyze` clean; all Flutter tests pass
- [ ] Manual end-to-end via gateway (`make docker-dev`): email invite →
      logged link → signed-out redemption → trip in "Shared with you"
