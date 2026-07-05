# Spec: Itinerary Item Editing

## Context

Itineraries are add-only today: the agent writes them and users can append a
place, but fixing anything — a wrong name, a place on the wrong day, an
unwanted stop, a bad order — requires re-prompting the AI. This is the most
common daily-use friction in the product. This feature makes individual
itinerary items editable, deletable (with undo), and reorderable without
involving the agent.

Deferred from `specs/itinerary-editing` ("edit/delete individual item by
hand", "drag-and-drop reordering", "undo/version history"): this delivers the
first two in menu form and a lightweight client-side undo for deletes.

## User Stories

- As a traveler, I want to rename a place, fix its city/day, or change its
  category and time of day, so the itinerary matches my actual plan.
- As a traveler, I want to remove a place I'm not going to visit — and undo
  that removal if I tapped it by mistake.
- As a traveler, I want to nudge a place up or down within its day so the
  visiting order is right.

## Acceptance Criteria

- [x] `PATCH /api/v1/trips/{id}/items/{itemId}` partially updates name,
      place_id, address, coordinates, category, time_of_day, city,
      day_trip_from, day. Absent fields keep their values. Category /
      time_of_day / day validation matches the add endpoint. Returns the
      updated item.
- [x] `DELETE /api/v1/trips/{id}/items/{itemId}` removes the item and closes
      the position gap in one transaction. Returns 204.
- [x] `PUT /api/v1/trips/{id}/items/order` takes `{"item_ids": [...]}` — the
      full item set in its new order — and reassigns positions 0..n-1 in one
      transaction. A list that doesn't exactly match the trip's current items
      (missing, extra, duplicate, unknown ids) returns 409 so a stale client
      can never clobber agent-written items.
- [x] `POST .../items` (add) accepts `day_trip_from`, so a deleted day-trip
      item can be restored faithfully by the undo path.
- [x] All three endpoints are owner-scoped (404 for another user's trip) and
      touch the trip's `updated_at`.
- [x] Attribution snapshots (`local_source_name`, `local_recommendation_id`)
      are not editable and survive edits.
- [x] Flutter: each itinerary tile gets an actions menu — Edit (bottom sheet:
      name, city, day, category, time of day), Move up / Move down (shown only
      when the neighbor is in the same day + hub + day-trip batch), Remove
      (SnackBar with Undo that re-adds the item).
- [x] Travel-time connectors, day grouping, and the map all reflect the
      change after each operation (full reload after mutate).

## Decisions

- **Granular endpoints, not full-list PUT sync.** The booking_todos PUT-sync
  precedent doesn't transfer: itinerary items are also written by the agent
  (`persistTrip`, `replaceTripSection`) and carry attribution snapshots that a
  stale full-list PUT would silently clobber. Granular ops are conflict-safe
  by construction; the reorder endpoint enforces set-equality (409) for the
  same reason.
- **Menu-based move instead of drag-and-drop.** Tiles are interleaved with
  travel connectors and day-trip sub-headers inside pinned sliver sections; a
  `ReorderableListView` would flatten that structure. Move up/down inside the
  tile menu delivers within-day reordering without a layout rewrite.
  Cross-day moves go through the edit sheet (change the day) — unambiguous
  about where the item lands.
- **Undo = client re-add.** No server tombstones (consistent with the undo
  deferral in `specs/itinerary-editing`); the restored item lands at the end
  of its day, which is close enough.
- The reorder endpoint accepts any full-trip permutation (future-proof for a
  drag UI); the current UI only ever submits within-day swaps.

## Contract Parity

| JSON key | Go type | Dart type | Nullable |
|---|---|---|---|
| `item_ids` (reorder req) | `[]string` | `List<String>` | no |
| PATCH request fields | `*string`/`*float64`/`*int` | absent-or-value in `Map<String, dynamic>` | yes (absent = keep) |
| PATCH response | `ItineraryItemResponse` | `ItineraryItem` | matches existing model |
| `day_trip_from` (add req) | `*string` | `String?` | yes |

## Out of Scope

- Drag-and-drop reordering (menu-based v1; contract already supports it).
- Undo/version history beyond the delete SnackBar.
- Editing accommodations, segments, or booking todos (separate feature).
- Clearing a set field to null via PATCH (COALESCE semantics; acceptable v1).
