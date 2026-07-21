# Spec: Calendar Export — Timed Items & Booking Detail

> **WHAT & WHY only.** No tech choices, file names, libraries, or code. If a
> sentence names a file or a package, it belongs in `plan.md`, not here.

## Context

The calendar export lagged behind the rest of the product. Every event was
all-day, so a day with four activities imported as four identical banners
stacked at the top of the day — useless as a schedule. Stays and transport
carried no provider, price, booked status, or booking link, so the calendar was
strictly less useful than both the app and the printed packet. This feature
turns itinerary items into real time-slotted events and brings booking detail
onto every calendar entry.

## User Stories

- As a **traveler**, I want my activities to occupy time slots in my calendar so
  that a day reads as a schedule instead of a pile of all-day banners.
- As a **traveler at a check-in desk**, I want the calendar entry for my stay or
  flight to show the provider, price note, booked status, and booking link so
  that I don't have to open the app.
- As a **traveler importing a whole trip**, I want the import to be labeled with
  my trip's name so it's identifiable among my other calendars.

## Acceptance Criteria

- [ ] An itinerary item tagged morning appears 09:00–12:00, afternoon
      13:00–17:00, and evening 19:00–22:00 on its trip day.
- [ ] Item times are floating: the event shows at those wall-clock hours in
      whatever timezone the traveler's device is set to, with no shifting.
- [ ] An item with no time-of-day remains an all-day event.
- [ ] Stays and transport remain all-day events (no clock data exists for them).
- [ ] A stay's calendar entry shows provider, price note, "Booked" when booked,
      and a readable short form of the booking link; the full link is attached
      as the event's URL.
- [ ] A transport entry shows the same, plus the traveler's own notes.
- [ ] An event with none of those fields shows no empty description or link.
- [ ] Importing the whole trip produces a calendar labeled with the trip title.
- [ ] Adding a single event and then importing the whole trip does not create a
      duplicate of that event.
- [ ] The Google Calendar button and the Apple (.ics) button on the same row
      produce the same event — same times, same title, same details.
- [ ] All text follows the traveler's language, matching the rest of the app.

## API Surface

No new endpoints; the two existing calendar downloads change their content only.

### `GET /api/v1/export/{token}/calendar.ics` and `.../event/{kind}/{id}.ics`
- **Purpose:** the trip (or one event) as a calendar file.
- **Request:** unchanged — signed token, plus the existing language selection.
- **Response:** calendar file per the rules above.
- **Errors:** unchanged opaque 404 for a bad/expired token or unknown event.

## Data Model

No new entities and no schema change. Item times are **derived from the existing
time-of-day bucket** — they are a product-level convention, not traveler-entered
clock data. Storing real start/end times per item remains the eventual upgrade;
until then the windows above are the promise.

## UI Behavior

- **Screen / surface:** unchanged — the per-event "Add to calendar" menu on
  stays, transport, and itinerary items, plus the trip menu's calendar export.
- **Happy path:** pick Google or Apple; the event lands with its time slot and
  booking detail.
- **States:** undated events still hide the affordance entirely.

## Edge Cases & Error States

- Unrecognized or legacy time-of-day values fall back to all-day rather than
  guessing a window.
- Booking links containing commas or semicolons must survive intact in the
  attached link.
- Long descriptions must remain valid calendar files (line-length limits).
- Multi-byte characters (accents, emoji) must never be corrupted by that
  line-length handling.

## Out of Scope

- Real per-item start/end time columns and any UI for editing them.
- Timed stays (check-in time) or transport (departure time).
- Booking todos and the packing checklist — deliberately not in the calendar.
- Changes to how the export is triggered, tokenized, or shared.

## Open Questions

None — the windows and the todo/checklist exclusion were decided with the owner
before implementation.
