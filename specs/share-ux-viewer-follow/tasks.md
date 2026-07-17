# Tasks: Native Share Sheet & Viewer Follow

> Dependency-ordered. Work top to bottom; verification is last.

## API (Go)

- [x] Role-aware collaborator upsert + `GetViewableTripByID` + role in list
      queries; `make api-sqlc`
- [x] Join accepts viewer tokens; shared-with-me/collaborators carry roles;
      self-leave (`collaborators/me`); `viewableTrip` in `getTripHandler`
      (no todos for viewers); analytics gate → viewable

## UI (Flutter)

- [x] `share_plus` + `lib/utils/share_link.dart` (`shareOrCopyLink`,
      iPad anchor rect); share menu labels per platform
- [x] Viewer read-only gating in trip detail + `BookingsSection.readOnly`;
      three-way banner; "Remove from my trips"
- [x] "Keep in my trips" on viewer links; trips-list viewer cards;
      "Manage access" sheet roles; `leaveTrip` service

## Verification

- [x] Full Go suite (3 new/replaced integration tests)
- [x] `flutter analyze` clean; all Flutter tests pass
- [ ] Manual: mobile share sheet; two-session viewer follow via gateway
