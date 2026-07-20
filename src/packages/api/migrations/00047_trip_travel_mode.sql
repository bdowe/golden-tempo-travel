-- +goose Up
-- How the traveler moves between cities on THIS trip ("we're driving").
-- Values align with trip_segments.mode: flight|car|train|bus|ferry, plus
-- 'mixed' for genuinely multi-mode trips. NULL = never stated, which keeps
-- the legacy flight-default behavior everywhere. Validated in Go
-- (allowedTravelModes), matching the status column's style.
ALTER TABLE trips ADD COLUMN travel_mode text;

-- +goose Down
ALTER TABLE trips DROP COLUMN IF EXISTS travel_mode;
