# Plan: Add to Itinerary from Local Recs, Events, and Guide Pins

> **HOW.** Translates `spec.md` into a file-level technical approach.

## Technical Approach

Everything rides on plumbing that already exists. The `itinerary_items`
snapshot columns (`local_source_name`, `local_recommendation_id`) shipped in
migration `00022` and `CreateItineraryItem` already inserts them — only the
agent's create path populated them. So: **no migration, no new query, no new
endpoint.** The work is (1) letting the public item-create handler accept and
return the two fields, (2) a reusable Flutter "Add to trip" bottom sheet fed
by a small payload struct that each surface builds from its own model, and
(3) whitelisting one new client analytics event. Guide pins render with
`LocalRecCard` already, so one card affordance covers two of the three
surfaces.

Key decisions:
- **Day is the "section".** The itinerary groups city → day → time_of_day,
  all derived from item fields; there is no stored section entity. The picker
  therefore offers a day choice (chips), defaulting to unscheduled, and the
  existing `insertPositionForDay` server logic slots the item correctly.
- **Dedupe = warn client-side, allow server-side.** After the user picks a
  trip, the sheet fetches that trip's detail (one GET, also needed to build
  the day chips) and checks for an existing item with the same
  `local_recommendation_id` (recs/pins) or case-insensitive name (events).
  The server stays permissive — snapshots are advisory by design.
- **UUID-shape validation only** for `local_recommendation_id`: parse or 400,
  never an existence check (snapshots must survive pin archival).
- **Attribution rendering is new Flutter work**: the fields were never in the
  trips API response nor the Dart model. Add them to `ItineraryItemResponse`
  (Go) and `ItineraryItem` (Dart), and render a credit line on the item tile.
  Agent-built trips get the credit line for free.

## Go API Changes

`src/packages/api/` (all `package main`):

- **`itinerary_item_handler.go`** — `AddItineraryItemRequest` gains
  `LocalSourceName *string` and `LocalRecommendationID *string`. Handler
  trims/normalizes, 400s on a non-UUID id, and passes both to the existing
  `CreateItineraryItemParams` (as `*string` / `pgtype.UUID`). Authz unchanged
  (`editableTrip`). Patch handler switches to the shared response builder so
  its response also carries the fields (the columns stay non-updatable —
  write-once snapshots).
- **`trip_handler.go`** — `ItineraryItemResponse` gains
  `local_source_name` / `local_recommendation_id` (both `omitempty`);
  new `toItineraryItemResponse` + `pgUUIDToStringPtr` helpers replace the
  inline struct literal in `toTripResponse`.
- **`itinerary_section.go`** — `locationFromItem` now round-trips the two
  snapshot fields, fixing a latent bug where an agent section rewrite dropped
  attribution from *kept* items (`itemParamsFromLocation` already read them
  back).
- **`analytics.go`** — `clientEventTypes` gains `itinerary_item_added`;
  `clientEventMetadataKeys` gains `source`, with a closed value set
  (`local_rec` / `event` / `guide_pin`) enforced in
  `sanitizeClientEventMetadata` because the key feeds dashboard GROUP BYs.
- **Queries/store:** none. `query/trips.sql` `CreateItineraryItem` already
  includes both columns; `make api-sqlc` is a no-op (verified).
- **Routes:** none (existing `POST /trips/{id}/items`, `POST /events`).

## Flutter Changes

`src/packages/flutter-app/lib/`:

- **Models** — `models/itinerary_item.dart`: add `localSourceName`
  (`local_source_name`) and `localRecommendationId`
  (`local_recommendation_id`), both `String?`; run
  `make flutter-build-models`.
- **Widget: `widgets/add_to_trip_sheet.dart`** (new) — the picker.
  - `AddToTripPayload`: `name`, `latitude`/`longitude` (`double?`), `city`,
    `address`, `placeId`, `category`, `localSourceName`,
    `localRecommendationId`, `eventDate`/`eventTime` (for day/time_of_day
    derivation), and `source` (`local_rec` | `event` | `guide_pin`).
    Factory constructors `fromLocalRec(rec, {source})` and `fromEvent(event)`
    own the field mapping from spec §UI Behavior.
  - `showAddToTripSheet(context, payload, {initialTripId})`:
    `showModalBottomSheet` (pattern: `AddStaySheet`), lists trips from
    `tripsProvider` (triggers `loadTrips()` when empty), on trip select
    fetches trip detail via `tripsApiServiceProvider.getTrip` to build day
    chips + run the duplicate check, derives event day/time-of-day from the
    trip's `startDate`/`endDate`, POSTs via the existing
    `addItineraryItem(tripId, body)` (body now includes the snapshot keys),
    fires `recordItineraryItemAdded`, pops, and shows the snackbar with a
    "View trip" action navigating to `TripDetailScreen`.
- **Surfaces:**
  - `widgets/local_rec_card.dart` — optional `onAddToTrip` callback renders
    an "Add to trip" action on the card (shown only when non-null, i.e.
    signed in).
  - `widgets/event_card.dart` — same optional callback (kept separate from
    the card's open-URL tap).
  - `screens/trip_detail_screen.dart` — wires both sections' cards with
    `initialTripId: trip.id` (`source: local_rec` / `event`).
  - `screens/local_guide_detail_screen.dart` — wires pins with
    `source: guide_pin`.
  - Auth gating: callbacks passed only when `authProvider` says signed in.
- **Attribution rendering** — `trip_detail_screen.dart` `_itemTile`: when
  `item.localSourceName != null`, a "Recommended by <name>" credit line in
  the LocalRecCard visual voice (`AppColors.toolLocal`).
- **Service** — `services/analytics_api_service.dart`: add
  `recordItineraryItemAdded({tripId, source})` (fire-and-forget, same shape
  as `recordBookingLinkClicked`).

## Contract Parity  ← anti-drift gate

| JSON key | Go type | Dart type | Nullable? | ✓ |
|----------|---------|-----------|-----------|---|
| `local_source_name` (item request) | `*string` | `String?` | yes | ☑ |
| `local_recommendation_id` (item request) | `*string` (UUID-validated) | `String?` | yes | ☑ |
| `local_source_name` (item response) | `*string,omitempty` | `String?` | yes | ☑ |
| `local_recommendation_id` (item response) | `*string,omitempty` | `String?` | yes | ☑ |
| `metadata.source` (analytics) | closed set string | `String` | no | ☑ |

## Cross-cutting

- **Env vars:** none.
- **Gateway:** no new paths.
- **CLAUDE.md:** note that the public item-create path is now a second writer
  of the attribution snapshots.

## Verification

- `make api-fmt && make api-vet`; `make api-sqlc` produces no diff.
- Go unit: `itinerary_section_test.go` — `locationFromItem` round-trips
  attribution through `itemParamsFromLocation`.
- Go integration (own DB `travel_test_w8c`):
  `itinerary_item_integration_test.go` — create with snapshots persists and
  returns them (trip response + store row); snapshots optional (absent →
  NULL); malformed id → 400; foreign trip → 404.
  `analytics_integration_test.go` — `itinerary_item_added` accepted with a
  valid `source`, bogus `source` value dropped.
- Flutter: `make flutter-build-models`; widget test drives the sheet against
  a fake `TripsApiService` and asserts the POST body includes the snapshot
  keys, plus the duplicate warning and event day derivation;
  `make flutter-test`; `flutter analyze --no-fatal-infos --fatal-warnings`.
- Manual: `make docker-dev`, walk spec acceptance criteria at
  `http://localhost:3000`.
