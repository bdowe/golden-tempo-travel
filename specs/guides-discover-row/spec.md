# Spec: Local Guides Discover Row

## Context

Published narrative guides (authored by named locals) are only reachable today
from within a trip's city-scoped "Local intel" section — a traveler who hasn't
started a trip for that city never sees them. The home screen should surface
the newest published guides across **all** cities as a horizontal discover row,
giving the locally-sourced content layer a front door and a browse entry point
into `LocalGuideDetailScreen`.

## User Stories

- As a **traveler**, I want to see recent local guides on the home screen so
  that I can discover locally-sourced trip ideas before I've planned anything.
- As a **traveler**, I want to tap a guide card and read the full guide (story,
  byline, pinned places, map) so that discovery flows straight into content.

## Acceptance Criteria

- [ ] The home screen shows a "Local guides" section between the recent-trip
      card and the "Planning toolkit" tile: a section header plus a
      horizontally scrollable row of guide cards.
- [ ] Each card shows the guide's hero image (branded fallback when missing or
      broken), title, city, and the local's name; tapping it opens the existing
      guide detail screen.
- [ ] The section shows guides from **multiple cities**, newest first, capped
      at 20.
- [ ] When there are no published guides, or the request is loading or fails,
      the entire section (header included) renders nothing — the home screen
      looks exactly as it did before this feature.
- [ ] Only `published` guides ever appear; drafts never leak.

## API Surface

### `GET /api/v1/local/guides` — contract parity

The `city` query parameter is now **optional** (it previously returned
`400 city is required` when blank).

- **`?city=<name>` (unchanged, backward compatible):** published guides for
  that city, newest first, with source attribution — exactly the prior
  behavior and response shape.
- **No / blank `city` (new):** the newest published guides across all cities,
  capped at 20, same row shape (guide fields + `source_name` /
  `source_photo_url`). Response is `{"city": "", "guides": [...]}`.
- **Degraded mode (no DB):** `{"city": "", "guides": []}` with 200, unchanged.
- **Errors:** 500 on a query failure; the blank-city 400 is removed.

## Data Model

No schema changes. Adds one read query (`ListPublishedGuides`): all
`status = 'published'` rows of `local_guides` joined with `local_sources`
attribution (same join as the per-city list), ordered `created_at DESC`,
limited by parameter.

## Out of Scope

- Pagination / "see all guides" screen.
- Personalization (ordering by traveler preferences or profile).
- Any change to the per-city guide list, guide detail, or admin curation flows.
