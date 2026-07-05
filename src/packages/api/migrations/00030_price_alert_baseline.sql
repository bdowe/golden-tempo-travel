-- +goose Up
-- Fixed any-drop reference price. last_checked_price re-baselined every
-- cycle, so slow cumulative declines never crossed the 5%/$5 threshold and a
-- spike-then-revert notified above the price the user was watching.
-- baseline_price is set once (client seed or first check) and only moves
-- forward via notifications (last_notified_price takes over as reference).
ALTER TABLE price_alerts ADD COLUMN baseline_price DOUBLE PRECISION;
UPDATE price_alerts SET baseline_price = last_checked_price;

-- +goose Down
ALTER TABLE price_alerts DROP COLUMN baseline_price;
