# Spec: Today Mode & Map Day-Filtering

## Context

A trip that is happening *right now* renders exactly like one planned for next
year: the itinerary opens at Day 1 and the map always shows every pin from the
whole trip. Mid-trip, the user's actual question is "what am I doing today, and
where?" — answering it takes manual scrolling through past days and squinting
at a map cluttered with places from other days. The outcome: opening a live
trip lands you on today's plan automatically, and a chip row on the map lets
you look at any single day — its places, its walking route, and where you're
sleeping that night — with the camera framed to just that day.

## User Stories

- As a **traveler on an active trip**, I want the itinerary to open scrolled to
  today's plan so that I don't wade through the days already behind me.
- As a **traveler on an active trip**, I want the map to open showing just
  today's places and route so that the map answers "where am I going today?"
- As a **trip owner**, I want to flip the map between All and any single day so
  that I can sanity-check one day's geography at a time.
- As a **recipient of a shared trip link**, I want the familiar whole-trip view
  with the option to filter by day so that someone else's "today" is never
  forced on me.

## Acceptance Criteria

### Today auto-scroll (trip detail)

- [ ] Opening a trip whose date range includes today (by the device's local
      date) scrolls the itinerary once, automatically, to today's day section,
      which is visibly highlighted as "today".
- [ ] The auto-scroll happens at most once per screen visit: silent background
      refreshes never re-trigger it, and it never fires while the refine panel
      is open.
- [ ] If the target day's section (or its city group) is collapsed, it expands
      first, then the scroll lands on it.
- [ ] If today has no itinerary items, the scroll targets the nearest prior
      day that has items; if no prior day has items, the nearest following day
      with items; if the trip has no day-tagged items at all, no scroll occurs.
- [ ] Trips without dates, and trips whose range is entirely in the past or
      future, open exactly as they do now (top of list, no highlight, no
      scroll).

### Map day-filter chips

- [ ] The trip map gains a chip row — `All · Day 1 · Day 2 · … · Day N` —
      where N is the trip's day count (the later of the date span and the
      highest day-tagged item).
- [ ] Selecting a day chip filters the map to that day: only that day's pins,
      the route line between them, their walking-time labels, and the stay(s)
      covering that night are shown. A stay covers a night checkout-exclusively:
      it shows on day *d* when `checkIn <= d < checkOut`.
- [ ] Changing chips re-frames the camera (auto-fit) to the newly visible
      pins/stays without the map remounting or flashing tiles.
- [ ] Selecting a day with nothing mappable shows an on-map message for that
      day; the chip row remains visible and usable (the chips never disappear
      because of an empty selection).
- [ ] Items without a day tag appear only under **All**, never under a day chip.
- [ ] When the trip's day count is 0 (no dates and no day-tagged items), the
      chip row is hidden entirely and the map behaves as today.
- [ ] On a live trip (today inside the date range), the map preselects today's
      day chip; otherwise **All** is preselected.

### Shared views, offline, and API

- [ ] Shared read-only trip views get the same chip row defaulting to **All**,
      and none of the Today behaviors (no auto-scroll, no highlight, no today
      preselection).
- [ ] Everything above works offline in view-only mode (chips filter cached
      data; no network required).
- [ ] No API changes: all behavior is derived client-side from data the app
      already receives.

## API Surface

None. No new endpoints, no request/response changes. Day membership, "today",
and stay coverage are all computed on the client from existing trip fields
(`start_date`, `end_date`, item `day`, stay `check_in`/`check_out`).

## Data Model

No persisted entities change. Client-side derived concepts only:

- **Today's trip day** — the 1-based day number the device's local date falls
  on within the trip's date range; undefined (absent) when the trip is undated,
  the dates don't parse, or today is outside the range.
- **Day count** — how many day chips to offer: the later of the trip's date
  span and the highest day tag on any item.
- **Stay-night coverage** — whether an accommodation covers the night of a
  given date: check-in date ≤ date < check-out date (checkout day excluded).

## UI Behavior

- **Surface:** trip detail screen (itinerary list + map) and the shared
  read-only trip screen (map only — no Today behaviors).
- **Happy path (live trip):** owner opens the trip mid-trip → list scrolls to
  today's highlighted section → map shows today's chip selected, today's pins,
  route, and tonight's stay → owner taps `Day 5` to preview → camera re-fits
  to Day 5 → taps `All` to see the whole trip again.
- **States:** day with no mappable places → on-map message with chips still
  shown; undated trip → no chips, no highlight; offline → identical filtering
  over cached data.

## Edge Cases & Error States

- Today is inside the range but that day has no items → scroll falls back to
  the nearest prior day with items, then nearest following, then no-op.
- Collapsed city group or day section containing the target → expanded before
  scrolling.
- Unparseable or missing dates anywhere degrade to the undated behavior — no
  crash, no chips (unless items carry day tags), no scroll.
- Timezones: "today" is the device's local calendar date; trip dates are
  date-only strings interpreted as local dates.
- A stay whose check-in/check-out is missing or unparseable never matches a
  day chip (it still shows under All).
- Day chips must reflect day tags beyond the date span (e.g. an item tagged
  Day 9 on a 7-day trip still yields a Day 9 chip).

## Out of Scope

- Persisting the selected chip or any server-side notion of "today".
- Filtering the itinerary *list* by day (chips are a map affordance only).
- Notifications / reminders about today's plan.
- Any change to the Go API or the shared-trip payload.

## Open Questions

None.
