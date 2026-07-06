# Spec: Offline Trip Cache

## Context

A traveler mid-trip is exactly the user most likely to open the app — and
exactly the user most likely to have no network (airplane mode, roaming off,
subway, island dead zone). Today the trips list and trip detail screens show a
spinner and then an error. Everything the traveler needs (the itinerary, the
day plan, booking references) was already downloaded on a previous visit; we
just threw it away. This feature keeps a local, read-only copy of
previously-loaded trips so the app degrades gracefully to "here's your saved
plan" instead of a dead end.

## User Stories

- As a **traveler with no connectivity**, I want to open the app and still see
  my trips list and full trip details (itinerary, bookings, to-dos), so my
  plan is usable exactly when I'm on the move.
- As a **traveler viewing a saved copy**, I want an unmistakable indicator of
  when that copy was saved, so I know how stale it might be.
- As a **traveler back online**, I want one tap to retry the live fetch, and
  the offline state to disappear automatically once a live load succeeds.
- As a **privacy-conscious user on a shared device**, I want my cached trips
  removed when I sign out or delete my account, so the next user can't read
  my plans.

## Acceptance Criteria

- [ ] After viewing the trips list online, disabling the network and reopening
  the list shows the same trips with an offline banner instead of an error.
- [ ] After viewing a trip's detail online, disabling the network and
  reopening that trip shows the full saved detail — itinerary items (grouped
  as usual), bookings, booking to-dos — with an offline banner.
- [ ] The banner reads "Offline — showing saved copy from <relative time>"
  (e.g. "5 minutes ago", "2 days ago") and offers a Retry action that
  re-attempts the live fetch.
- [ ] While offline-serving, every mutation affordance is disabled or hidden:
  rename, edit dates, change status, Refine with AI (all entry points: trip,
  city, day), add place, edit/reorder/delete itinerary items, add/delete
  bookings and stays/transport, toggle booking to-dos, share, delete trip.
  Any deep entry point that can't be visually disabled shows a "you're
  offline" notice instead of firing a request.
- [ ] Serving from cache happens **only** for network-level failures
  (no connection, timeout). An HTTP error response — 403, 404, 500 — shows
  the normal error state and never falls back to the cache (a revoked or
  deleted trip must not resurrect from a stale copy).
- [ ] A trip never loaded before is not available offline; the normal error +
  Retry state shows.
- [ ] When a live fetch later succeeds, the banner disappears and the screen
  behaves exactly as before this feature existed.
- [ ] At most the last 10 viewed trip details are kept; opening an 11th evicts
  the least-recently-viewed one.
- [ ] Signing out (including "sign out everywhere") and deleting the account
  remove all cached trip data for that user from the device.
- [ ] Two users on the same device never see each other's cached trips.

## Not Available Offline (explicit)

These remain online-only; they must fail gracefully (disabled affordance,
quiet empty section, or a clear error) rather than half-work:

- Chat / AI refine (all refine panels and seeds).
- Route optimization and travel-time computation.
- Flight, event, ferry, local-recommendation and guide lookups (their embedded
  sections simply don't render, as they already do on lookup failure).
- All mutations (anything that would POST/PATCH/PUT/DELETE).
- Shared-with-me trips and the public shared-trip view (not cached in v1).
- Pull-to-refresh still works as "try live again" — it either succeeds and
  exits offline mode or leaves the saved copy in place.

## API Surface

None. This feature is entirely client-side; no new endpoints and no changes
to existing request/response contracts.

## Data Model

Client-side cache only (no server entities):

- **Cached trip list** — the last successfully fetched trips list for a user,
  plus the timestamp it was saved.
- **Cached trip detail** — the last successfully fetched full detail of one
  trip (itinerary items, accommodations, segments, booking to-dos), plus the
  timestamp it was saved. At most 10 per user, evicted least-recently-viewed.
- All cached entries are keyed by the signed-in user's id; anonymous sessions
  cache nothing (trips require sign-in).

## UI Behavior

- **Trips list:** loads live as today. On a network-level failure with a
  cached copy present, the list renders from the copy with the offline banner
  pinned above it; Retry re-runs the live load. Without a cached copy the
  existing "Could not load trips" empty state shows.
- **Trip detail:** loads live as today. On a network-level failure of the
  initial (loud) load with a cached copy present, the saved detail renders
  with the banner above the scroll area and mutations disabled. Silent
  refreshes keep their existing behavior (failures keep showing the current
  trip quietly). A later successful load clears the banner and re-enables
  everything.
- **Staleness:** relative time ("just now", "N minutes/hours/days ago"),
  computed from the saved-at timestamp at render time.

## Edge Cases & Error States

- **HTTP 4xx/5xx:** never served from cache (see acceptance criteria).
- **Corrupt/unreadable cache entry:** treated as a miss; the normal error
  state shows. Reads never crash the app.
- **Cache write failure** (storage full, platform quirk): silently ignored —
  caching is best-effort and must never affect the online path.
- **Deleted trip:** deleting a trip (online) also removes its cached detail
  and removes it from the cached list, so offline mode can't reopen it.
- **Large trips:** payloads are stored as JSON strings in on-device
  preferences (web: localStorage). This bounds practical size (~5 MB origin
  quota on web); the 10-trip cap plus single-list entry keeps usage well
  under it for realistic trips. Revisit with a real database (drift/sqflite)
  if trips grow media-heavy. This trade-off is accepted for v1.

## Out of Scope

- Offline **mutations** / write queueing / conflict resolution.
- Caching shared-with-me trips, public share links, guides, local recs,
  flights, events, ferries.
- Proactive connectivity detection (no connectivity_plus); offline mode is
  entered reactively when a fetch fails at the network level.
- Background sync / prefetching trips never opened.
- Images/map tiles offline (maps may render blank offline; the itinerary list
  is the offline surface).
