# Tasks: Shared-Trip Freshness & Edit Attribution

> Dependency-ordered. Work top to bottom; verification is last.

## API (Go)

- [x] Migration 00035 `trips.updated_by`
- [x] `TouchTrip(id, updated_by)` + `GetTripStatusByID` +
      `HasActiveCollaborators` + `CreateTrip` creator stamp; `make api-sqlc`
- [x] `touchedBy` helper; stamps in item/accommodation/segment/booking-todo
      handlers, agent todo tools, `replaceTripSection` (actor param),
      patchTrip; sync handler explicitly excluded
- [x] `tripStatusHandler` + route; `TripResponse.updated_by_name`/`shared`

## Models & codegen (Flutter)

- [x] `Trip.updatedByName` / `Trip.shared`; `make flutter-build-models`
- [x] Contract Parity table complete

## UI (Flutter)

- [x] `getTripStatus` service method
- [x] Lifecycle-aware 25s poll in trip detail (`_syncStatusPolling` /
      `_statusTick`), guarded against offline/panel/in-flight refresh
- [x] "Updated by X · 2m ago" header line

## Verification

- [x] `go vet` + full `go test` pass (3 new integration tests)
- [x] `flutter analyze` clean; all Flutter tests pass
- [ ] Manual two-session check via gateway (`make docker-dev`)
