-- +goose Up
ALTER TABLE traveler_preferences ADD COLUMN home_airport text; -- IATA code, e.g. BOS

-- +goose Down
ALTER TABLE traveler_preferences DROP COLUMN IF EXISTS home_airport;
