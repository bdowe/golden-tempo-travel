# Spec: Shared-Trip Freshness & Edit Attribution

## Context

Co-planners on a shared trip only see each other's changes after a manual
pull-to-refresh, and nothing says who changed what — two people planning
together are effectively working blind between reloads. This feature makes an
open shared trip feel current without heavy machinery: the screen quietly
checks for remote edits and refreshes itself, and a subtle "Updated by Maria ·
2m ago" line credits the last editor. It deliberately stops short of realtime
sync, presence, or notifications.

## User Stories

- As a **co-planner**, I want **the trip screen to pick up my friend's changes
  on its own** so that **we can plan together without constantly refreshing**.
- As a **trip owner**, I want **to see who last changed the trip and when** so
  that **a surprise edit has a name attached**.
- As a **traveler**, I want **my own edits left unlabeled** so that **the
  attribution line only appears when it carries news**.

## Acceptance Criteria

- [ ] With a shared trip open on two devices, an edit on one appears on the
      other within ~30 seconds, with no user action.
- [ ] The trip header shows "Updated by {name} · {relative time}" when the
      last content edit was made by someone other than the viewer; it never
      shows for the viewer's own edits.
- [ ] Every content edit is attributed: items, stays, transport segments,
      booking-checklist changes, title/date/status changes, and AI
      refinements — whether made in the UI or by the agent.
- [ ] Merely opening or reloading a trip never marks it as edited (the
      passive booking-checklist sync does not stamp attribution).
- [ ] Polling only happens while a shared trip is open, in the foreground,
      and online; unshared trips never poll.
- [ ] Strangers cannot read a trip's freshness status (same not-found posture
      as the trip itself).

## API Surface

### `GET /api/v1/trips/{id}/status`
- **Purpose:** cheap freshness poll for an open shared trip.
- **Request:** authenticated; no body.
- **Response:** `updated_at`, plus `updated_by` (user id) and
  `updated_by_name` when the last editor is known.
- **Errors:** 404 for non-members and unknown ids (no existence leak); 401
  unauthenticated.

### `GET /api/v1/trips/{id}` (response additions)
- `updated_by_name`: display name of the last editor, omitted when unknown or
  when the caller made the edit.
- `shared`: true on an owner's trip that has active co-planners — the signal
  that polling is worthwhile (editors poll based on their access alone).

## Data Model

- **Trip** gains a *last edited by* reference (nullable; unknown for
  pre-feature rows, cleared if the editor's account is deleted). All content
  writes record it through the single existing "touch the trip" choke point —
  the same place a future activity log or notification outbox would hook in.

## UI Behavior

- **Trip detail:** while a shared trip is open, the screen checks freshness
  every ~25s; when the server's `updated_at` is newer than the loaded copy,
  the existing silent refresh runs (no spinner, no scroll jump). The
  attribution line renders under the header controls in muted body-small
  type.
- **Lifecycle:** polling stops when the app backgrounds and restarts (with an
  immediate catch-up check) on resume; it never runs offline, while the
  refine panel is streaming, or while another refresh is in flight.
- **States:** poll failures are swallowed — no error UI, no offline flip.

## Edge Cases & Error States

- Editor's account deleted: attribution reverts to unknown; no broken name.
- Two clients polling simultaneously: reads are cheap single-row lookups;
  refreshes coalesce through the existing silent-refresh queue.
- Clock skew is irrelevant: the client compares the server's own timestamps.

## Out of Scope

- WebSockets/SSE between users, presence, typing indicators.
- Push or in-app notifications; unread badges.
- Per-item "edited by" chips or an activity-feed screen.
- Polling on the trips list.

## Open Questions

None — resolved during planning: 25s interval, self-attribution hidden,
activity log deferred (the touch choke point is the future hook).
