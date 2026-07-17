-- +goose Up
-- Baggage tier on price alerts (baggage-aware flight search). The checker
-- searches with the alert's tier and tracks the EFFECTIVE price (fare + bag
-- fee when the bag isn't included), so a watch created from a carry_on or
-- checked search doesn't silently regress to watching bag-less basic fares.
ALTER TABLE price_alerts
    ADD COLUMN baggage TEXT NOT NULL DEFAULT 'personal_item'
        CHECK (baggage IN ('personal_item', 'carry_on', 'checked'));

-- The active-duplicate unique key gains baggage: the same route/date watched
-- with and without a bag tracks different prices, so both may be active.
DROP INDEX price_alerts_active_unique_idx;
CREATE UNIQUE INDEX price_alerts_active_unique_idx ON price_alerts
    (user_id, origin, destination, depart_date,
     COALESCE(return_date, '0001-01-01'::date), cabin_class, adults, flex_days, baggage)
    WHERE status = 'active';

-- +goose Down
DROP INDEX price_alerts_active_unique_idx;
CREATE UNIQUE INDEX price_alerts_active_unique_idx ON price_alerts
    (user_id, origin, destination, depart_date,
     COALESCE(return_date, '0001-01-01'::date), cabin_class, adults, flex_days)
    WHERE status = 'active';
ALTER TABLE price_alerts DROP COLUMN baggage;
