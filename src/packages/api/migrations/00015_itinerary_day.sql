-- +goose Up
-- The trip day this place belongs to (1-based, increasing chronologically); all
-- places on the same day share the same number. Used to group the itinerary into
-- "Day 1 / Day 2…" sections within each city. NULL for legacy items.
ALTER TABLE itinerary_items ADD COLUMN day integer;

-- +goose Down
ALTER TABLE itinerary_items DROP COLUMN IF EXISTS day;
