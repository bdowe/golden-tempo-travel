# Tasks: Collaborator AI Refine

> Dependency-ordered. Work top to bottom; verification is last.

## API (Go)

- [x] `GetTripForUpdate` query + `make api-sqlc`
- [x] Row lock in `replaceTripSection` and the reorder transaction
- [x] Trip-bound `/plan` binding → `GetEditableTripByID`; stash
      `boundTripOwnerID` on the session
- [x] `runGetTripTool` + `checkBookingTodoSession` accept the bound trip via
      the editable seam
- [x] Null `chat_id` in editor responses (`getTripHandler`,
      `listSharedWithMeHandler`)
- [x] `is_collaborator` on the `trip_refined` event

## UI (Flutter)

- [x] Drop owner gates from `_openRefine`, `_openChat`, per-day/city refine
      icons, chat FAB
- [x] Header shows co-planning banner + Refine button for editors

## Verification

- [x] `go vet` + full `go test` (with `TEST_DATABASE_URL`) pass
- [x] New integration tests: collaborator refine end-to-end, stranger refusal,
      chat_id omission
- [x] `flutter analyze` clean
- [ ] Manual end-to-end via gateway (`make docker-dev`): co-planner refines,
      owner sees the in-place update
