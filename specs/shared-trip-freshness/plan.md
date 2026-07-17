# Plan: Shared-Trip Freshness & Edit Attribution

> **HOW.** See `../../CLAUDE.md` for repo conventions.

## Technical Approach

One nullable column (`trips.updated_by`), stamped through the existing
`TouchTrip` choke point, plus a cheap authorized status endpoint the client
polls on a guarded 25s timer. No new tables: the UI only needs "who edited
last", and the choke point is where a future `trip_activity` log/notification
outbox would hook in. Passive load paths (booking-todo sync) explicitly never
stamp — otherwise every reader looks like an editor and polling clients chase
each other's refreshes.

## Go API Changes

- Migration `migrations/00035_trip_updated_by.sql`: `ALTER TABLE trips ADD
  COLUMN updated_by uuid REFERENCES users(id) ON DELETE SET NULL`.
- `query/trips.sql`: `TouchTrip` gains `updated_by = $2` (invariant comment:
  real edits only); new `GetTripStatusByID` (owner-or-collaborator WHERE) and
  `HasActiveCollaborators`; `CreateTrip` stamps the creator. `make api-sqlc`.
- `trip_handler.go`: `touchedBy(tripID, r)` param helper;
  `tripStatusHandler` (`GET /trips/{id}/status`, default limiter — it's
  polled); `TripResponse` gains `updated_by_name` (omitted for self-edits) +
  `shared` (owner-side EXISTS); patchTrip stamps post-update.
- Stamp sites added: accommodation add/delete, segment add/delete,
  booking-todo add/patch/delete (`_ = TouchTrip(...)` best-effort after
  commit), agent booking-todo tools (`touchTripAs`), `replaceTripSection`
  (actor param threaded from the plan session, also covers collaborator
  refines). **Excluded**: `syncBookingTodosHandler`.
- Route in `main.go` next to the trip detail routes.

## Flutter Changes

- `models/trip.dart`: `updatedByName`, `shared` (+ codegen).
- `services/trips_api_service.dart`: `getTripStatus(id)` returning a record.
- `screens/trip_detail_screen.dart`: `WidgetsBindingObserver` mixin;
  `Timer.periodic(25s)` started/stopped by `_syncStatusPolling()` after every
  load and on lifecycle changes; `_statusTick()` skips offline / panel-open /
  refresh-in-flight and calls the existing `_refresh()` when the server
  timestamp is newer; "Updated by X · 2m ago" line in the header card
  (`_relativeTime` helper).

## Contract Parity  ← anti-drift gate

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| `updated_by_name` | `*string` | `String?` | yes | ✓ |
| `shared` | `bool,omitempty` | `bool?` | yes | ✓ |
| status `updated_at` | `time.Time` | `DateTime` (parsed) | no | ✓ |
| status `updated_by` | `*string` | `String?` | yes | ✓ |
| status `updated_by_name` | `*string` | `String?` | yes | ✓ |

## Cross-cutting

- No env vars; no gateway changes; migration runs on boot as usual.

## Verification

- Integration tests (`trip_status_integration_test.go`): status authz
  (owner/editor 200, stranger 404, anon 401); collaborator edit → owner sees
  attribution, editor's own view omits it, status carries the editor id;
  passive booking-todo sync stamps nothing.
- `make api-fmt && make api-vet`; full `go test`; `make flutter-build-models`;
  `flutter analyze` + `flutter test`.
- Manual: two browser sessions on one shared trip; edit on one side appears
  on the other within ~30s with the attribution line.
