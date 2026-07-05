-- +goose Up
-- When a local pin seeds an itinerary item, snapshot the local's name onto the
-- item so a saved trip still reads "Recommended by Ana" even if the pin is later
-- archived. Nullable, no FK on the recommendation id — the snapshot must outlive
-- the source row (same rationale as the nullable columns added in 00006/00011).
ALTER TABLE itinerary_items ADD COLUMN local_source_name text;
ALTER TABLE itinerary_items ADD COLUMN local_recommendation_id uuid;

-- +goose Down
ALTER TABLE itinerary_items DROP COLUMN IF EXISTS local_recommendation_id;
ALTER TABLE itinerary_items DROP COLUMN IF EXISTS local_source_name;
