-- +goose Up
-- When a place is a day trip from the city the traveler is staying in, this
-- holds that hub city (e.g. 'Paris' for a day trip to Versailles); the item's
-- own `city` stays the actual town. NULL for normal in-city places.
ALTER TABLE itinerary_items ADD COLUMN day_trip_from text;

-- +goose Down
ALTER TABLE itinerary_items DROP COLUMN IF EXISTS day_trip_from;
