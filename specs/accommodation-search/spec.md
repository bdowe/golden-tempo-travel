# Spec: Accommodations

> **WHAT & WHY only.**

## Context

A trip needs somewhere to stay. Travelers want Airbnb and Booking.com as the
primary sources, but neither offers an open search API (Booking's is gated behind
affiliate approval; Airbnb has none). So this feature lets a traveler **browse
Airbnb + Booking.com via generated search links** for their destination/dates and
**save the stays they choose onto their trip** (manually, or by pasting an Airbnb
listing URL that the app enriches). The design is source-agnostic so real in-app
listings can be added later without disruption. Depends on trips + accounts.

## User Stories

- As a **traveler**, I want to open Airbnb/Booking.com pre-filled with my
  destination and dates so I can browse real stays.
- As a **traveler**, I want to save the place I'm staying onto my trip (and add
  several for a multi-city trip).
- As a **traveler**, I want to paste an Airbnb listing link and have its details
  filled in for me.
- As a **traveler**, I want to remove a saved stay.

## Acceptance Criteria

- [ ] For a destination (+ optional dates/guests), the app provides Airbnb and
      Booking.com search links that open the right results on those sites.
- [ ] A signed-in user can add one or more accommodations to their own trip; they
      appear in the trip detail.
- [ ] Pasting an Airbnb listing URL pre-fills name/price/location before saving.
- [ ] A user can delete a saved accommodation.
- [ ] A user cannot add to or modify another user's trip.
- [ ] The agent can surface the same browse links during planning.

## API Surface

- `GET /api/v1/accommodation-links?destination=&check_in=&check_out=&guests=` →
  list of `{provider, url}` (Airbnb + Booking.com). No auth required.
- `POST /api/v1/trips/{id}/accommodations` (auth, owner) → add a stay; returns it.
- `DELETE /api/v1/trips/{id}/accommodations/{accId}` (auth, owner) → 204.
- `GET /api/v1/trips/{id}` (existing) now also returns an `accommodations` list.

## Data Model

- **Accommodation** — belongs to a trip (many per trip). Fields: name; provider
  (airbnb/booking/other); listing URL (optional); address + coordinates
  (optional); check-in/check-out dates (optional); a free-text price note
  (optional, e.g. "~$120/night").

## UI Behavior

- **Trip detail → Stays section:** lists saved accommodations (with delete), a
  **Find stays** action that opens the Airbnb + Booking.com links, and **Add a
  stay** (manual fields, or paste an Airbnb URL to pre-fill).
- **Agent:** when discussing where to stay, surfaces "Browse on Airbnb / Booking"
  links (no in-app listings).

## Edge Cases & Error States

- Missing destination on the links endpoint → 400.
- Adding/deleting on a trip you don't own → 404 (existence not leaked).
- Unauthenticated trip-scoped calls → 401.
- Airbnb URL that fails to parse → user can still save manually.
- Empty/zero accommodations → trip detail renders a "no stays yet" state.

## Out of Scope

- Real in-app Airbnb/Booking listings, live pricing/availability (await Booking
  Demand API approval).
- Payments/booking confirmation (Phase 6 handoff/checklist).
- Ranking by interests; editing a saved stay (add/delete only this phase).

## Resolved Decisions

- **Sources:** Airbnb + Booking.com via **deep-link handoff** now; provider-
  agnostic interface so a real listing API slots in later.
- **Multiple** accommodations per trip.
- **Trip-UI-primary** plus a light agent browse-link tool.
- Reuse the existing Airbnb single-listing parser for pasted URLs only (no search scraping).
