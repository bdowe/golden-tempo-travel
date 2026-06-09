-- +goose Up
-- A short prose overview of the trip, shown under the title. The `title` column
-- now holds a concise name. NULL for legacy trips (their long summary still
-- lives in `title` and the UI falls back accordingly).
ALTER TABLE trips ADD COLUMN summary text;

-- +goose Down
ALTER TABLE trips DROP COLUMN IF EXISTS summary;
