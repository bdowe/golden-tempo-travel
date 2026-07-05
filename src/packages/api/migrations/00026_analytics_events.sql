-- +goose Up
-- First-party analytics event log (specs/instrumentation-events). Append-only,
-- never user-visible. trip_id is a loose reference by design: an event
-- outlives the trip it points at, so no FK. No PII beyond the user id.
CREATE TABLE analytics_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    event_type TEXT NOT NULL,
    trip_id UUID,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX analytics_events_type_time_idx ON analytics_events (event_type, created_at);
CREATE INDEX analytics_events_user_idx ON analytics_events (user_id, created_at);

-- +goose Down
DROP TABLE analytics_events;
