-- +goose Up
-- Anonymous /plan sessions are now instrumented too: a null user_id marks an
-- unauthenticated caller, so total AI spend covers everyone while per-user
-- funnel queries filter to user_id IS NOT NULL.
ALTER TABLE analytics_events ALTER COLUMN user_id DROP NOT NULL;

-- +goose Down
DELETE FROM analytics_events WHERE user_id IS NULL;
ALTER TABLE analytics_events ALTER COLUMN user_id SET NOT NULL;
