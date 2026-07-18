-- +goose Up
-- Itinerary-derived draft bookings ("Suggested" stays/transport) live in the
-- same tables as user-entered rows. auto=true rows are owned by the client's
-- booking-drafts sync (like booking_todos.auto); dismissed=true is a tombstone
-- that keeps the auto_key so a dismissed draft can't be re-seeded while its
-- itinerary leg still exists. Pre-existing rows default to auto=false
-- (user-confirmed) and are never touched by the sync.
ALTER TABLE accommodations
    ADD COLUMN auto      boolean NOT NULL DEFAULT false,
    ADD COLUMN auto_key  text,
    ADD COLUMN dismissed boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX idx_accommodations_trip_auto_key
    ON accommodations(trip_id, auto_key) WHERE auto_key IS NOT NULL;

ALTER TABLE trip_segments
    ADD COLUMN auto      boolean NOT NULL DEFAULT false,
    ADD COLUMN auto_key  text,
    ADD COLUMN dismissed boolean NOT NULL DEFAULT false;
CREATE UNIQUE INDEX idx_trip_segments_trip_auto_key
    ON trip_segments(trip_id, auto_key) WHERE auto_key IS NOT NULL;

-- +goose Down
DROP INDEX IF EXISTS idx_trip_segments_trip_auto_key;
ALTER TABLE trip_segments
    DROP COLUMN IF EXISTS dismissed,
    DROP COLUMN IF EXISTS auto_key,
    DROP COLUMN IF EXISTS auto;

DROP INDEX IF EXISTS idx_accommodations_trip_auto_key;
ALTER TABLE accommodations
    DROP COLUMN IF EXISTS dismissed,
    DROP COLUMN IF EXISTS auto_key,
    DROP COLUMN IF EXISTS auto;
