-- +goose Up
-- Who last touched the trip's content — the "Updated by Maria · 2m ago"
-- attribution for shared trips (specs/shared-trip-freshness). NULL means
-- unknown (pre-feature rows). updated_at itself is trigger-maintained.
-- All content writes stamp this via the TouchTrip choke point; a future
-- trip_activity log / notification outbox would hang off that same choke
-- point rather than adding columns here.
ALTER TABLE trips ADD COLUMN updated_by uuid REFERENCES users(id) ON DELETE SET NULL;

-- +goose Down
ALTER TABLE trips DROP COLUMN updated_by;
