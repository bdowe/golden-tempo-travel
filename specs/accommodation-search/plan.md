# Plan: Accommodations

> **HOW.** See `../../CLAUDE.md`. Mirrors the trip-model patterns.

## Technical Approach
A provider-agnostic accommodation layer: an `AccommodationProvider` interface with
Airbnb/Booking `SearchURL` builders (deep-link handoff today; a listing-returning
provider can be added later behind the same package). An `accommodations` table
(many per trip) with add/list/delete behind `authMiddleware` + trip-ownership; the
trip-detail response gains an `accommodations` array. A light agent `suggest_stays`
tool surfaces the same links.

## Go API Changes
- **Migration `migrations/00005_accommodations.sql`:** `accommodations` (id, `trip_id`
  FK CASCADE, name NOT NULL, provider, url, address, latitude/longitude, check_in/check_out
  dates, price_note, timestamps + `set_updated_at` trigger, index on trip_id).
- **`query/accommodations.sql`:** `CreateAccommodation`, `ListAccommodationsByTrip`,
  `DeleteAccommodation` (`WHERE id=$1 AND trip_id=$2`). `make api-sqlc`.
- **`accommodation_service.go`:** `AccommodationQuery`, `AccommodationProvider`
  interface, `airbnbProvider`/`bookingProvider` `SearchURL` (encoded destination +
  checkin/checkout + guests; affiliate params from `BOOKING_AFFILIATE_ID`/`AIRBNB_AFFILIATE_ID`
  when set). `providerLinks(q)` helper returning `[]{provider,url}`.
- **`accommodation_handler.go`:** `accommodationLinksHandler` (parse query, 400 if no
  destination), `addAccommodationHandler` (verify trip ownership via `GetTripByIDAndOwner`,
  then `CreateAccommodation`), `deleteAccommodationHandler` (404 if 0 rows). Reuse
  `userFromContext`, `writeJSON`/`writeJSONError`, `pgtype.Date` parse from `trip_handler.go`.
- **`trip_handler.go`:** extend `TripResponse` with `Accommodations []AccommodationResponse`
  and load them in `getTripHandler`.
- **`plan_handler.go`:** `suggest_stays` tool (authed) → emits provider links via SSE.
- **`main.go`:** register `GET /accommodation-links` (open), `POST /trips/{id}/accommodations`
  + `DELETE /trips/{id}/accommodations/{accId}` (authed); startup logs. **`.env.sample`:** affiliate vars.

## Flutter Changes
- `models/accommodation.dart` (+ `.g.dart`); add `accommodations` to `models/trip.dart`.
- `services/accommodations_api_service.dart`: `accommodationLinks`, `addAccommodation`, `deleteAccommodation` (bearer from `ApiClient`).
- `screens/trip_detail_screen.dart`: **Stays** section — list + delete, **Find stays**
  (open links via `url_launcher`), **Add a stay** (manual / paste Airbnb URL → `/airbnb/parse` prefill).
- `pubspec.yaml`: add `url_launcher`.

## Contract Parity
| JSON key | Go | Dart | Nullable |
|---|---|---|---|
| `id` | `string` | `String` | no |
| `name` | `string` | `String` | no |
| `provider` | `*string` | `String?` | yes |
| `url` | `*string` | `String?` | yes |
| `address` | `*string` | `String?` | yes |
| `latitude`/`longitude` | `*float64` | `double?` | yes |
| `check_in`/`check_out` | `*string` (YYYY-MM-DD) | `String?` | yes |
| `price_note` | `*string` | `String?` | yes |

## Verification
1. `make api-sqlc`, `api-fmt`/`api-vet`; migration applies.
2. `go test` for `SearchURL` builders (host/path, encoded destination, dates/guests, affiliate-only-when-set).
3. curl: `/accommodation-links` valid URLs; add → appears in `GET /trips/{id}`; delete; other-user → 404; unauth → 401.
4. `flutter analyze` + `build web`; Stays section find/add/delete works.
