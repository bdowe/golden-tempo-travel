-- +goose Up
-- Alert events (specs/price-alerts-v2): one row per triggered price-drop
-- notification — the persistent spine of the in-app notification center.
-- Written by the checker in the same idempotent block that marks the alert
-- notified, so "one email" and "one event" are the same decision. user_id is
-- denormalized from the alert (the analytics_events convention) so per-user
-- feed/badge reads never join through price_alerts. previous_price is the
-- reference the drop was judged against (last notified, else baseline) —
-- NULL when a target-mode alert triggers on its very first observation.
-- Prices are DOUBLE PRECISION to match price_alerts (sqlc emits *float64).
CREATE TABLE alert_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    alert_id UUID NOT NULL REFERENCES price_alerts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    price DOUBLE PRECISION NOT NULL,
    currency TEXT NOT NULL,
    previous_price DOUBLE PRECISION,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);

-- Feed reads are always per-user, newest first.
CREATE INDEX alert_events_user_time_idx ON alert_events (user_id, occurred_at DESC);
-- The unread badge count scans only unread rows.
CREATE INDEX alert_events_unread_idx ON alert_events (user_id) WHERE read_at IS NULL;

-- +goose Down
DROP TABLE alert_events;
