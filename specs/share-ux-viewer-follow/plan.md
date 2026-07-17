# Plan: Native Share Sheet & Viewer Follow

> **HOW.** See `../../CLAUDE.md` for repo conventions.

## Technical Approach

Viewer follow is a role, not a new mechanism: `trip_collaborators.role`
already exists, so the join upsert learns roles (upgrade-never-downgrade via
`ON CONFLICT ... DO UPDATE ... CASE`) and reads move from the editor-only
seam to a new `GetViewableTripByID` that returns the caller's effective
access. Every mutation handler keeps `editableTrip` untouched, so viewers
are read-only for free. The share sheet is a thin utility: share_plus on
mobile (with the iPad-mandatory `sharePositionOrigin`), clipboard elsewhere.

## Go API Changes

- `query/collaborators.sql`: role-aware `CreateTripCollaborator :one`
  (upsert + RETURNING role); `GetViewableTripByID` (owner or any active
  member + access column); `role` added to `ListCollaboratorsByOwnerAndChat`
  and `ListLatestCollaboratedTripsForUser`. `make api-sqlc`.
- `collaborator_handler.go`: join drops the viewer 403 and passes the
  share's role; `viewableTrip` helper; shared-with-me `Access` from the row;
  `CollaboratorResponse.Role`; `removeCollaboratorHandler` special-cases
  `userId == "me"` (self-leave via `GetViewableTripByID` + revoke,
  `collaborator_left` event). `collaborator_joined` gains role metadata.
- `trip_handler.go` `getTripHandler`: `viewableTrip`; booking todos skipped
  for viewers; `Access` from the query; chat_id null for all non-owners.
- `invite_handler.go`: accept passes `Role: "editor"` explicitly.
- `analytics.go` trip-id validation gate → `GetViewableTripByID` (viewers'
  client events still attribute).
- Freshness endpoints already role-agnostic (any active collaborator).

## Flutter Changes

- `pubspec.yaml`: `share_plus: ^12.0.2` (13.x doesn't resolve with the
  current SDK constraint; the `SharePlus.instance.share(ShareParams)` API is
  present since v11).
- New `lib/utils/share_link.dart`: `appBasePath`, `shareUrl(token)`,
  `shareUsesNativeSheet` (kIsWeb/defaultTargetPlatform — no dart:io), and
  `shareOrCopyLink(...)` with `sharePositionOrigin`.
- `trip_detail_screen.dart`: `_shareLink`/`_inviteCoPlanner` use the helper
  (anchor rect from a GlobalKey on the share menu); platform-aware menu
  labels; "Manage access" sheet title + per-row role labels; viewer gating
  via `_readOnly` (`Trip.canEdit`): rename/dates/status, item menus, Add
  place (list + map empty state), Add booking, `BookingsSection.readOnly`;
  three-way banner (owner button / editor co-planning / viewer
  "view only"); app-bar "Remove from my trips" → `leaveTrip` + confirm;
  polling condition widened to all non-owners.
- `bookings_section.dart`: `readOnly` flag hides add buttons + delete icons.
- `trips_api_service.dart`: `leaveTrip`; `listCollaborators` gains `role`.
- `shared_trip_screen.dart`: viewer links get primary "Keep in my trips"
  (same join flow — server decides the role) + secondary save-a-copy.
- `trips_list_screen.dart`: viewer cards (eye icon, "Shared by {owner}").

## Contract Parity  ← anti-drift gate

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| trip `access` (now incl. 'viewer') | `string,omitempty` | `String?` (`canEdit` helper) | yes | ✓ |
| collaborator `role` | `string` | `String` (record field) | no | ✓ |
| join `access` | `string` | (unused by client) | no | ✓ |

## Cross-cutting

- No env vars, no migration, no gateway changes. share_plus needs no
  platform config for text shares.

## Verification

- Integration tests (`collaborator_integration_test.go`): viewer join →
  read-only follow (200 read without todos/chat_id; item/patch/todo
  mutations 404; shared-with-me + collaborators list roles; status poll OK);
  role transitions (viewer→editor upgrade, no downgrade); self-leave (+
  owner self-leave 404). Full Go suite green.
- `flutter analyze` clean; all Flutter tests pass.
- Manual: mobile share sheet on a device/simulator (iPad popover anchor!);
  viewer follow end-to-end in two browser sessions.
