# Tasks: Accommodations

> Dependency-ordered. `[P]` = parallel-safe. Verification last.

## Schema & codegen (Go)
- [ ] `migrations/00005_accommodations.sql` (table + trigger + index)
- [ ] `query/accommodations.sql` (Create / ListByTrip / Delete)
- [ ] `make api-sqlc`; store compiles

## Providers & API (Go)
- [ ] `accommodation_service.go`: provider interface + Airbnb/Booking `SearchURL` + affiliate env + `providerLinks`
- [ ] `accommodation_handler.go`: links / add / delete (ownership via `GetTripByIDAndOwner`)
- [ ] Extend `TripResponse` + `getTripHandler` with `accommodations`
- [ ] `suggest_stays` agent tool in `plan_handler.go`
- [ ] Register routes in `main.go`; add affiliate vars to `.env.sample`

## Verify backend
- [ ] `api-fmt`/`api-vet` clean
- [ ] `go test` for `SearchURL` builders
- [ ] curl: links / add / list-in-trip / delete / 404 / 401

## Flutter
- [ ] [P] `models/accommodation.dart` (+ build-models); extend `trip.dart`
- [ ] [P] `services/accommodations_api_service.dart`
- [ ] `pubspec.yaml`: `url_launcher`
- [ ] `trip_detail_screen.dart`: Stays section (list/delete, Find stays, Add a stay w/ Airbnb paste)
- [ ] Complete Contract Parity table in `plan.md`

## Verify frontend
- [ ] `flutter analyze` clean; `flutter build web`
- [ ] Stays section lists/deletes; Find stays opens links; Add via Airbnb URL prefills
