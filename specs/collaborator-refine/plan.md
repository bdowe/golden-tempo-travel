# Plan: Collaborator AI Refine

> **HOW.** Translates `spec.md` into a file-level technical approach. See
> `../../CLAUDE.md` for repo conventions.

## Technical Approach

The refine panel already runs a trip-bound `/plan` session whose only write
tool (`update_itinerary_section`) patches the bound trip row in place — it
never calls `persistTrip`, so there is no lineage-fork risk on this path. The
whole feature is therefore an authorization change: swap the trip-bound
binding and the two in-session owner guards from `GetTripByIDAndOwner` to the
existing `GetEditableTripByID` seam (owner OR active editor collaborator), and
un-gate the Flutter refine entry points. Two supporting changes keep the
system honest: a `FOR UPDATE` trip-row lock serializes concurrent
whole-itinerary rewrites (pre-existing duplicate-items race under READ
COMMITTED), and editor-facing responses null out `chat_id` so a collaborator
can never seed a freeform `/plan` with the owner's session key and fork the
lineage under their own account.

## Go API Changes

- `query/trips.sql`: new `GetTripForUpdate :one` (`SELECT … FOR UPDATE`);
  regenerate with `make api-sqlc`.
- `itinerary_section.go` `replaceTripSection`: lock the trip row first inside
  the transaction.
- `itinerary_item_handler.go` `reorderItineraryItemsHandler`: same lock at the
  top of the reorder transaction (makes the stale-set 409 reliable).
- `plan_handler.go` (trip binding): `GetEditableTripByID` instead of
  `GetTripByIDAndOwner`; stash the trip's owner id on the session
  (`boundTripOwnerID`) for analytics.
- `plan_tools_extra.go`:
  - `runGetTripTool` gains a `boundTripID` parameter — the bound trip resolves
    via `GetEditableTripByID`; all other trip ids (and the list-trips branch)
    stay caller-owned.
  - `checkBookingTodoSession`: bound trip → editable seam; anything else stays
    owner-scoped.
- `trip_handler.go` `getTripHandler` + `collaborator_handler.go`
  `listSharedWithMeHandler`: `resp.ChatID = nil` for editor access.
- `plan_tool_registry.go`: `planSession.boundTripOwnerID` field;
  `trip_refined` event gains `is_collaborator`.
- Unchanged on purpose: `refineTripHandler` (owner-only, no app callers);
  session persistence rules (trip-bound sessions never write
  `plan_chat_sessions`); free-cap metering (per-caller).

## Flutter Changes

`lib/screens/trip_detail_screen.dart` only — no models/services/providers:
- `_openRefine` / `_openChat`: drop the owner belt-and-braces guards.
- Per-day refine icon, city-header refine icon, chat FAB: drop `isOwner` from
  the gates (offline gate stays).
- Header card: editors now get the co-planning banner **and** the
  "Refine with AI" button (previously either/or).
- Share menu and delete stay owner-only.

## Contract Parity  ← anti-drift gate

No new JSON fields. One behavioral row:

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| `chat_id` | `*string` (now nil for editors) | `String?` | yes | ✓ |

Flutter consumers of `chatId` are owner/admin-only surfaces (version history,
resumable chats), each already null-guarded.

## Cross-cutting

- No env vars, no migrations, no gateway changes.

## Verification

- `make api-fmt && make api-vet`; full `go test` with `TEST_DATABASE_URL`.
- New integration tests (`collaborator_integration_test.go`):
  `TestCollaboratorCanRefineViaAgent` (fake-Anthropic drives
  `update_itinerary_section`; asserts single trip row, in-place item rewrite,
  owner read), `TestStrangerCannotRefineViaAgent`,
  `TestCollaboratorResponsesOmitChatID`.
- `make flutter-analyze` / `make flutter-test`.
- Manual: two accounts via `make docker-dev`; co-planner refines a shared
  trip; owner sees the change on reload; double-refine leaves a single clean
  item set.
