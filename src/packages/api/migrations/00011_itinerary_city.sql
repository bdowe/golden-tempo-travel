-- +goose Up
-- City/locality the AI assigns to each itinerary place so the itinerary groups
-- by city. Nullable; legacy/manual items leave it unset and fall back to parsing
-- the address.
ALTER TABLE itinerary_items ADD COLUMN city text;

-- +goose Down
ALTER TABLE itinerary_items DROP COLUMN IF EXISTS city;
