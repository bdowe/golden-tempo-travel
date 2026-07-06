# Spec: Add to Itinerary from Local Recs, Events, and Guide Pins

> Close the browse → trip loop: anything worth seeing in the app can be put on
> a trip in two taps.

## Context

The app surfaces three kinds of browseable inspiration — locally-sourced
recommendations, live events, and the pins inside a local's guide — but none
of them can be placed on a trip. The loop dead-ends: a traveler reads "Ana's
favorite tasca", nods, and has to re-type it into the add-place dialog by
hand (losing Ana's credit entirely, since the manual path can't carry
attribution). This feature adds an "Add to trip" affordance to all three
surfaces, a trip-and-day picker, and carries the local-source attribution
snapshot onto the created item — so a trip built by browsing credits the
locals the same way an agent-built trip does.

## User Stories

- As a **traveler browsing local recommendations**, I want to **add a rec to
  one of my trips in place** so that **I don't have to re-type it into the
  itinerary by hand**.
- As a **traveler reading a local's guide**, I want to **add a guide pin to a
  trip** so that **the guide becomes a plan, not just reading material**.
- As a **traveler looking at events during my trip window**, I want to **put
  an event on the right trip day** so that **my schedule reflects it**.
- As a **local whose pick gets added**, I want **my name to stay on the item**
  so that **the trip still credits me** (same promise the agent makes).
- As a **trip owner**, I want to **see who recommended a place directly on my
  itinerary** so that **I remember why it's there**.

## Acceptance Criteria

- [ ] Every local recommendation card, every event card, and every pin on a
      guide's detail page shows an "Add to trip" action for signed-in users.
- [ ] Tapping it opens a picker listing the user's trips; picking a trip and
      confirming creates an itinerary item on that trip and shows a success
      confirmation with a shortcut to view the trip.
- [ ] When the surface lives inside a trip's own detail page (local intel and
      events sections), that trip is preselected in the picker.
- [ ] After choosing a trip, the user may optionally choose which day the item
      lands on (days are how this product groups an itinerary; there is no
      other "section" concept). Default is unscheduled — the item appends to
      the end of the trip. For an event whose date falls inside the chosen
      trip's dates, the matching day is pre-selected.
- [ ] An item added from a local recommendation or guide pin carries the
      local's name and the recommendation's id as snapshots; the itinerary
      then shows a "Recommended by <name>" credit line on that item, exactly
      as it would on an agent-built trip.
- [ ] An item added from an event carries the event's venue/city and — when
      derivable from the trip dates — the day and a morning/afternoon/evening
      slot from the event's start time.
- [ ] Adding the same recommendation to a trip that already contains it is
      **allowed but warned**: the picker shows an "already on this trip"
      notice and the confirm button reads "Add anyway". (Snapshots are
      advisory; the server never rejects duplicates.)
- [ ] Anonymous users do not see the "Add to trip" action (trips require an
      account; the browse surfaces stay fully public).
- [ ] Only the trip owner or an editor-collaborator can add an item; anyone
      else is rejected exactly like other itinerary mutations.
- [ ] Each successful add records an `itinerary_item_added` analytics event
      tagged with its source surface (local rec / event / guide pin), and a
      bogus source tag is dropped rather than stored.
- [ ] Attribution snapshots survive later agent edits: when the agent rewrites
      a section of the trip, items it keeps retain their credit line.

## API Surface

### `POST /api/v1/trips/{id}/items` (auth — existing endpoint, extended)
- **Purpose:** create an itinerary item; now optionally carrying local-source
  attribution snapshots.
- **Request (new optional fields):**
  - `local_source_name` — the display name of the local who recommended the
    place. Stored verbatim as a snapshot; blank/whitespace is treated as
    absent.
  - `local_recommendation_id` — the id of the recommendation pin the item was
    created from. Must be a well-formed UUID when present, but is **not**
    checked for existence — the snapshot must survive the pin being archived
    later, so a dangling id is legal by design.
  - All existing fields (`name`, coordinates, `category`, `time_of_day`,
    `city`, `day`, …) behave as before; both new fields default to absent for
    existing callers.
- **Response:** unchanged shape (the updated trip); itinerary items now also
  expose `local_source_name` and `local_recommendation_id` when set. This
  applies to every response that embeds itinerary items (trip detail, item
  patch), so clients can render the credit line and detect duplicates.
- **Errors:** malformed `local_recommendation_id` → 400. Authorization is
  unchanged: not the owner/editor → 404.

### `POST /api/v1/events` (existing client-analytics endpoint, extended)
- **Purpose:** accept `itinerary_item_added` as a client-recorded event type.
- **Request:** `event_type: "itinerary_item_added"`, optional `trip_id`
  (verified against the caller's access, as today), metadata `source` limited
  to exactly `local_rec`, `event`, or `guide_pin` — any other value for
  `source` is dropped (the dashboard groups on it, so free-form values must
  not reach storage).
- **Response/Errors:** unchanged (202 accepted; unknown event types still 400).

## Data Model

No new entities and no schema change. The two snapshot fields
(`local_source_name`, `local_recommendation_id`) already exist on itinerary
items — nullable, no foreign key, written until now only by the AI agent's
trip-create path. This feature makes the public create path a second writer
and exposes both fields on reads. Their meaning is unchanged: a permanent
credit-at-time-of-adding, deliberately decoupled from the recommendation's
lifecycle.

## UI Behavior

- **Surfaces:**
  - Local recommendation cards (trip detail "Local intel" section, and
    anywhere else the card appears).
  - Event cards (trip detail "Events while you're here" section).
  - Guide pins on a guide's detail page (rendered with the same card as local
    recommendations; they carry their own pin id and local's name).
- **Happy path:**
  1. Tap "Add to trip" on a card.
  2. A bottom sheet lists the user's trips (current trip preselected when
     applicable). If the user has no trips, the sheet says so and offers
     nothing to pick (creating a trip is out of scope here).
  3. Optionally pick a day (chips: Unscheduled, Day 1…N). Events with a date
     inside the trip window get the matching day pre-selected.
  4. Confirm. On success the sheet closes and a snackbar confirms
     "Added to <trip>", with a "View trip" action that opens the trip.
- **Field mapping:**
  - *Local rec / guide pin* → name, coordinates (when the pin has them),
    city, category (same attraction/restaurant vocabulary), place id,
    plus `local_source_name` (the pin's local) and `local_recommendation_id`
    (the pin's id). The tip/quote text is **not** copied — itinerary items
    have no notes field (out of scope).
  - *Event* → name, coordinates (when real, not the 0,0 placeholder), city,
    venue as the address, category `attraction`, day (when the event date
    falls inside the trip's date range), time-of-day derived from the start
    time (before noon → morning, noon–5pm → afternoon, later → evening). No
    attribution snapshots — events are not locally sourced.
- **Attribution rendering:** an itinerary item with a local-source name shows
  a compact "Recommended by <name>" credit line in the trip's item list, in
  the same visual voice as the recommendation cards. This appears for items
  created here *and* for agent-created items (which stored the snapshot all
  along but never displayed it).
- **States:** picker loading (trips fetching), empty (no trips), duplicate
  warning ("already on this trip" + "Add anyway"), submit in-flight
  (disabled button), error (inline message, sheet stays open), success
  (snackbar + optional navigation).

## Edge Cases & Error States

- **Duplicate adds:** warn, allow. A place counts as already on the trip when
  an item carries the same `local_recommendation_id`, or — covering events
  (which have no id) and manually-typed duplicates — the same name
  (case-insensitive). The server never dedupes.
- **Missing coordinates:** a local rec may lack coordinates (unpublished
  drafts can't, but the model allows null); the item is created without them
  and simply doesn't appear on the map — the established behavior for
  coordinate-less items.
- **Event outside the trip window / trip has no dates:** no day is
  pre-selected; the item defaults to unscheduled.
- **Trip list fails to load:** the sheet shows an error state with retry; no
  item is created.
- **Analytics failures:** never surfaced; the add succeeds regardless
  (tracking is fire-and-forget, established convention).
- **Malformed recommendation id from a client:** 400 with a clear message;
  a well-formed id pointing at a deleted/archived pin is accepted silently.

## Out of Scope

- Creating a new trip from the picker (the picker only lists existing trips).
- A notes/description field on itinerary items (events' descriptions and
  recs' tips are not copied anywhere).
- Server-side duplicate rejection or any uniqueness constraint.
- Adding accommodations/segments from browse surfaces (items only).
- Editing attribution snapshots after creation (they remain write-once).
- Surfacing "which trips already contain this rec" on the browse cards
  themselves.

## Open Questions

None — the decisions above (day-as-section, warn-but-allow dedupe, no notes
field) were resolved during planning.
