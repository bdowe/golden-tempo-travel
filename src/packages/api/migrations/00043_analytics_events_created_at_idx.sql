-- +goose Up
-- Bare created_at index for the admin activity tail (RecentAnalyticsEvents in
-- query/admin.sql): ORDER BY created_at DESC LIMIT N was a top-N heap scan —
-- the composite indexes from 00026 (event_type/user_id + created_at) don't
-- serve an unfiltered time-ordered scan. DESC to match the query's ordering.
CREATE INDEX IF NOT EXISTS analytics_events_created_at_idx
    ON analytics_events (created_at DESC);

-- +goose Down
DROP INDEX IF EXISTS analytics_events_created_at_idx;
