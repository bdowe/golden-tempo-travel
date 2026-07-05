-- name: CreatePriceAlert :one
INSERT INTO price_alerts (
    user_id, trip_id, origin, destination, depart_date, return_date,
    cabin_class, adults, target_price, currency, last_checked_price,
    last_checked_at, baseline_price
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $11)
RETURNING *;

-- name: ListPriceAlertsByUser :many
SELECT * FROM price_alerts
WHERE user_id = $1
ORDER BY created_at DESC;

-- name: GetPriceAlertForUser :one
SELECT * FROM price_alerts
WHERE id = $1 AND user_id = $2;

-- name: CountActivePriceAlertsByUser :one
SELECT count(*) FROM price_alerts
WHERE user_id = $1 AND status = 'active';

-- name: UpdatePriceAlert :one
UPDATE price_alerts
SET status = $3,
    target_price = $4,
    updated_at = now()
WHERE id = $1 AND user_id = $2
RETURNING *;

-- name: DeletePriceAlert :execrows
DELETE FROM price_alerts
WHERE id = $1 AND user_id = $2;

-- name: ListDuePriceAlerts :many
-- Active alerts not yet checked in this cycle, oldest-checked first. The
-- caller passes the freshness cutoff (now - check interval) and batch size.
SELECT sqlc.embed(price_alerts), users.email AS owner_email
FROM price_alerts
JOIN users ON users.id = price_alerts.user_id
WHERE price_alerts.status = 'active'
  AND price_alerts.depart_date >= CURRENT_DATE
  AND (price_alerts.last_checked_at IS NULL OR price_alerts.last_checked_at < $1)
ORDER BY price_alerts.last_checked_at ASC NULLS FIRST
LIMIT $2;

-- name: MarkPriceAlertChecked :exec
UPDATE price_alerts
SET last_checked_price = $2,
    baseline_price = COALESCE(baseline_price, $2),
    currency = COALESCE(currency, $3),
    last_checked_at = now(),
    updated_at = now()
WHERE id = $1;

-- name: TouchPriceAlerts :exec
-- Failed or skipped checks (provider error, currency mismatch) advance only
-- the timestamp so the alert rotates to the back of the due queue instead of
-- retrying every tick, and no cross-currency price pollutes the row.
UPDATE price_alerts
SET last_checked_at = now(), updated_at = now()
WHERE id = ANY($1::uuid[]);

-- name: MarkPriceAlertNotified :exec
UPDATE price_alerts
SET last_notified_price = $2,
    last_notified_at = now(),
    updated_at = now()
WHERE id = $1;

-- name: ExpirePastPriceAlerts :execrows
UPDATE price_alerts
SET status = 'expired', updated_at = now()
WHERE status = 'active' AND depart_date < CURRENT_DATE;
