# Spec: Trip Sharing v1

## Context

Sharing is the product's viral loop (docs/sales-pitch.md) and was entirely
absent: no share links, no export, no way to show a trip to anyone. This
feature lets an owner mint an unguessable read-only link, lets anyone open it
without an account, and lets a signed-in viewer save a copy to their own
trips. Deferred from specs/trip-model ("sharing / public links",
"duplicate/copy a trip").

Real-time collaborative editing is explicitly OUT of this wave; the data
model is shaped to grow into it (a `role` column that later admits 'editor').

## User Stories

- As a trip owner, I want to share my itinerary with a friend via a link, so
  they can see the plan without creating an account.
- As a trip owner, I want the link to keep showing my latest version after I
  refine the trip with the AI, and I want to be able to turn sharing off.
- As a viewer, I want to save a copy of a shared trip into my own account and
  adapt it from there.

## Design

- **Shares bind to the chat_id lineage, not a trips row.** Every agent
  refinement appends a new trips version row; a row-bound token would pin
  viewers to a stale version. Token → chat_id → latest version row.
- `trip_shares` table (migration 00024): id, chat_id, owner_id (FK cascade),
  token (unique, 32 random bytes hex — same generator as session tokens),
  role (default 'viewer'), created_at, revoked_at. A separate table (vs a
  column on trips) gives revocation, multiple links, and the collaboration
  growth path.
- Legacy trips with NULL chat_id get one assigned on first share (same
  mechanism as refine).
- Flutter web hash URLs: `https://<host>/#/share/<token>` — refresh-safe with
  zero nginx changes. `onGenerateRoute` in main.dart routes `/share/{token}`
  to `SharedTripScreen` outside AuthGate; everything else falls through to
  the existing AuthGate flow.

## Acceptance Criteria

- [x] `POST /api/v1/trips/{id}/share` (auth) mints a viewer link; idempotent
      per lineage (sharing twice reuses the token). Returns token/role/created_at.
- [x] `DELETE /api/v1/trips/{id}/share` (auth) revokes all active links for
      the lineage; revoked links 404.
- [x] `GET /api/v1/shared/{token}` (public) returns the lineage's latest
      version: trip + items + accommodations + segments + owner display name.
      Booking todos, profile data, and chat_id are excluded. Unknown, revoked,
      and empty-lineage tokens are indistinguishable 404s.
- [x] `POST /api/v1/shared/{token}/duplicate` (auth) copies the latest
      version (items with attribution snapshots, stays, segments — not
      booking todos) into a fresh draft lineage owned by the caller, titled
      "<title> (copy)".
- [x] Flutter: share menu in trip detail (copy link / turn off sharing);
      `SharedTripScreen` renders title, owner, dates, summary, map, items
      grouped by hub city, stays, and a "Save a copy to my trips" CTA that
      routes through sign-in when needed and lands on the Trips tab.

## Contract Parity

| JSON key | Go type | Dart type | Nullable |
|---|---|---|---|
| `token` / `role` | `string` | `String` | no |
| `created_at` | `time.Time` | (unused client-side) | no |
| `trip` | `TripResponse` | `Trip` | no |
| `owner_name` | `string` | `String` | no (server defaults "A traveler") |

## Out of Scope

- Real-time / multi-user editing (role column reserved).
- Path-style URLs (needs nginx try_files + url_strategy; cosmetic).
- OG/link-preview meta tags (needs server-side rendering).
- share_plus native share sheets (clipboard copy v1).
- Public pages for events/local recs on the shared view.
