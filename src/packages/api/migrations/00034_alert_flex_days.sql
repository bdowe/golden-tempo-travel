-- +goose Up
-- Flexible departure dates (specs/price-alerts-v2, PR 3). flex_days is the
-- half-width of the watched departure window: a value N fans one alert out to
-- 2N+1 exact-date Duffel searches per cycle (checker fan-out), reported as the
-- cheapest matching date. Hard-capped at ±3 by a CHECK so provider spend can
-- only grow linearly and bounded — the per-cycle batch limiter absorbs the
-- multiplier (a wider window consumes more of the budget, not a bigger one).
ALTER TABLE price_alerts
    ADD COLUMN flex_days SMALLINT NOT NULL DEFAULT 0
        CHECK (flex_days >= 0 AND flex_days <= 3);

-- The active-duplicate unique key gains flex_days: a ±3 watch and an exact
-- watch on the same route/date are different alerts (different search cost and
-- different notifications), so both may be active at once.
DROP INDEX price_alerts_active_unique_idx;
CREATE UNIQUE INDEX price_alerts_active_unique_idx ON price_alerts
    (user_id, origin, destination, depart_date,
     COALESCE(return_date, '0001-01-01'::date), cabin_class, adults, flex_days)
    WHERE status = 'active';

-- The winning date inside a flexible window, recorded on the notification so
-- the feed and email can name it ("cheapest on Tue Jul 15"). NULL for the
-- exact-date default (flex_days = 0), where it always equals depart_date.
ALTER TABLE alert_events
    ADD COLUMN matched_departure_date DATE;

-- +goose Down
ALTER TABLE alert_events DROP COLUMN matched_departure_date;
DROP INDEX price_alerts_active_unique_idx;
CREATE UNIQUE INDEX price_alerts_active_unique_idx ON price_alerts
    (user_id, origin, destination, depart_date,
     COALESCE(return_date, '0001-01-01'::date), cabin_class, adults)
    WHERE status = 'active';
ALTER TABLE price_alerts DROP COLUMN flex_days;
