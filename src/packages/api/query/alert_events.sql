-- name: InsertAlertEvent :one
INSERT INTO alert_events (alert_id, user_id, price, currency, previous_price)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: ListAlertEventsByUser :many
-- The joined alert columns give the client the route/dates context inline so
-- rendering a notification never needs a second request. The join is inner on
-- purpose: deleting an alert cascades its events away.
SELECT alert_events.id, alert_events.alert_id, alert_events.price,
       alert_events.currency, alert_events.previous_price,
       alert_events.occurred_at, alert_events.read_at,
       price_alerts.origin, price_alerts.destination,
       price_alerts.depart_date, price_alerts.return_date,
       price_alerts.target_price, price_alerts.status AS alert_status
FROM alert_events
JOIN price_alerts ON price_alerts.id = alert_events.alert_id
WHERE alert_events.user_id = $1
ORDER BY alert_events.occurred_at DESC, alert_events.id DESC
LIMIT $2;

-- name: MarkAlertEventsRead :execrows
-- Mark-all is the v1 read model (specs/price-alerts-v2): opening the
-- notification center clears the badge wholesale. No per-event variant yet.
UPDATE alert_events
SET read_at = now()
WHERE user_id = $1 AND read_at IS NULL;

-- name: CountUnreadAlertEvents :one
SELECT count(*) FROM alert_events
WHERE user_id = $1 AND read_at IS NULL;
