-- +goose Up
-- Price alerts (specs/price-alerts): a watched flight route + the watch
-- state. Prices are DOUBLE PRECISION on purpose — sqlc emits *float64 to
-- match FlightOffer.Price, and cent precision is irrelevant for display and
-- threshold comparison. last_notified_price is the idempotency anchor: the
-- checker never re-notifies at or above it.
CREATE TABLE price_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES trips(id) ON DELETE SET NULL,
    origin TEXT NOT NULL,
    destination TEXT NOT NULL,
    depart_date DATE NOT NULL,
    return_date DATE,
    cabin_class TEXT NOT NULL DEFAULT 'economy',
    adults INT NOT NULL DEFAULT 1,
    target_price DOUBLE PRECISION,
    currency TEXT,
    last_checked_price DOUBLE PRECISION,
    last_checked_at TIMESTAMPTZ,
    last_notified_price DOUBLE PRECISION,
    last_notified_at TIMESTAMPTZ,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX price_alerts_user_idx ON price_alerts (user_id);
CREATE INDEX price_alerts_due_idx ON price_alerts (last_checked_at NULLS FIRST)
    WHERE status = 'active';
-- One active alert per exact watched search per user.
CREATE UNIQUE INDEX price_alerts_active_unique_idx ON price_alerts
    (user_id, origin, destination, depart_date,
     COALESCE(return_date, '0001-01-01'::date), cabin_class, adults)
    WHERE status = 'active';

-- +goose Down
DROP TABLE price_alerts;
