-- +goose Up
-- Manual drag order for the bookings hub ("Your bookings" stays + transport).
-- Default 9999 (not 0) so every pre-existing row and every future insert
-- (manual adds, seeded drafts, trip copies) ties at 9999 and falls through to
-- the date/created_at tiebreak — today's order is preserved exactly until the
-- user first drags, which renumbers that group 0..n-1; rows added afterwards
-- sink to the bottom. Same convention as custom booking_todos, but via the DB
-- default: no insert path enumerates position explicitly.
ALTER TABLE accommodations ADD COLUMN position int NOT NULL DEFAULT 9999;
ALTER TABLE trip_segments ADD COLUMN position int NOT NULL DEFAULT 9999;

-- +goose Down
ALTER TABLE trip_segments DROP COLUMN IF EXISTS position;
ALTER TABLE accommodations DROP COLUMN IF EXISTS position;
