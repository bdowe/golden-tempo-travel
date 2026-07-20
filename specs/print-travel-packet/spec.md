# Spec: Print Travel Packet

> **WHAT & WHY only.** No tech choices, file names, libraries, or code. If a
> sentence names a file or a package, it belongs in `plan.md`, not here.

## Context

The existing "Print / Save as PDF" export renders a flat dump: the itinerary
grouped by city, then separate accommodation, transport, and checklist lists.
On paper mid-trip that layout forces constant cross-referencing — "what's
happening *today*, where am I sleeping *tonight*?" — and it omits the trip
summary, budget, weather, and booking details entirely. This feature turns the
printed page into a travel agent-style **day-by-day packet**: everything for a
given day in one place, followed by compact reference sections.

## User Stories

- As a **traveler on the road**, I want a printed page per day showing that
  day's activities, transport, weather, and tonight's stay so that I can follow
  my trip without a phone.
- As a **trip owner**, I want booking details (provider, price notes, links,
  booked status) visible on paper so that the printout works as a booking
  reference at check-in desks.
- As a **budget-conscious traveler**, I want my budget and expense breakdown in
  the printout so that the packet doubles as a spending reference.

## Acceptance Criteria

- [ ] The print page opens from the existing trip-menu "Print / Save as PDF"
      action with no change to how it is triggered.
- [ ] The page header shows the trip title and date range; the trip summary
      paragraph appears beneath it when one exists.
- [ ] The body renders one section per calendar day of the trip, labeled
      "Day N · Weekday, Month D — City".
- [ ] A day section shows, in order: a weather line (when available), transport
      departing/arriving that day, the day's itinerary items (time-of-day,
      address, "Recommended by" attribution), and a "Tonight" block for the
      accommodation covering that night.
- [ ] The first night of a stay shows a check-in note; the last night shows the
      check-out date; a stay never appears on its check-out day.
- [ ] Days inside the trip range with no planned items still render (with
      weather/stay/transport and a "No plans yet" note).
- [ ] Items without an assigned day appear in an "Unscheduled" section after
      the day pages, grouped as before.
- [ ] A day consisting entirely of day-trip items is labeled with the
      destination and a "Day trip from <hub>" subline.
- [ ] Stays and transport carry provider, price note, booked status, and the
      booking link rendered as short visible text (readable on paper).
- [ ] A Budget section shows the target (with currency), expenses grouped by
      category with subtotals, total spent, and remaining — only when a budget
      or expenses exist.
- [ ] Weather shows real forecasts for near-term days and "Typical:" last-year
      values for far-out days; weather being unavailable never breaks or blanks
      the page.
- [ ] The Booking checklist and Packing checklist sections remain at the end,
      unchanged.
- [ ] A trip with no dates falls back to relative "Day N" sections with flat
      accommodation/transport reference lists (no weather).
- [ ] Printing (Cmd+P / Save as PDF) avoids splitting a day section or a single
      row across a page break where it fits.
- [ ] The calendar (.ics) export continues to work exactly as before.

## API Surface

No new endpoints. The existing token-gated print page changes its rendered
content only:

### `GET /api/v1/export/{token}/print.html`
- **Purpose:** printable day-by-day travel packet for the trip the signed token
  grants access to.
- **Request:** unchanged (signed token in path; 1-hour validity).
- **Response:** HTML page per the layout above.
- **Errors:** unchanged — invalid/expired token yields the existing friendly
  404 page.

## Data Model

No new entities. The page now *reads* (in addition to what it already read):
the trip summary, the trip budget and its expenses, and per-city weather
(looked up live, never stored).

## UI Behavior

- **Screen / surface:** browser tab opened by the trip menu's
  "Print / Save as PDF" action; user prints via the browser.
- **Happy path:** open menu → Print / Save as PDF → new tab shows the packet →
  Cmd+P.
- **States:** expired token → friendly "link isn't available" page; trip with
  no content → existing "nothing to export yet" message; weather/budget
  unavailable → those lines/sections are simply absent.

## Edge Cases & Error States

- Item day numbers beyond the trip's date range extend the day list; absurd
  day numbers (beyond a 60-day cap) fall into Unscheduled instead of rendering
  thousands of sections.
- Transport with only an arrival date attaches to the arrival day; transport
  with no dates goes to an "Other transport" reference list.
- Stays with no valid dates go to an "Accommodations" reference list.
- Weather lookups are bounded (a few seconds, a handful of cities); any
  failure or out-of-window date silently omits that day's weather line.
- Budget lookups failing silently omit the Budget section.

## Out of Scope

- Changing how the export is triggered, tokenized, or shared (no Flutter work).
- Maps, photos, or QR codes on the printout.
- Trip Health findings, local-recommendation browsing, or events on the
  printout.
- Changes to the .ics calendar export content.

## Open Questions

None — layout and content scope were decided with the owner before
implementation.
