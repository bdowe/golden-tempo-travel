-- +goose Up
-- Generalized in-app notifications feed (Wave 16). Supersedes alert_events as
-- the notification-center spine: alert_events was welded to price_alerts (every
-- column a flight field, the list query INNER JOINed price_alerts), so it could
-- never carry a trip reminder, a collaborator edit, or an invite-accepted. This
-- table is type-agnostic — the discriminator is `type` and the render data is a
-- `payload` jsonb the client switches on. user_id is denormalized (the
-- analytics_events/alert_events convention) so per-user feed and badge reads
-- never join. trip_id is a nullable soft link (many notifications relate to a
-- trip) that nulls rather than cascades so a deleted trip leaves its history.
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL,
    payload JSONB NOT NULL DEFAULT '{}',
    trip_id UUID REFERENCES trips(id) ON DELETE SET NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Feed reads are always per-user, newest first.
CREATE INDEX notifications_user_time_idx ON notifications (user_id, created_at DESC);
-- The unread badge count scans only unread rows.
CREATE INDEX notifications_unread_idx ON notifications (user_id) WHERE read_at IS NULL;

-- Backfill the existing price-drop feed so the new center shows full history on
-- day one. Each alert_events row becomes a 'price_drop' notification whose
-- payload carries exactly the fields ListAlertEventsByUser joined in (route,
-- dates, prices, matched date, alert status) so the client renders it without a
-- second request. previous_price / return_date / matched_departure_date /
-- target_price stay JSON null when absent — the client already tolerates that.
INSERT INTO notifications (user_id, type, payload, trip_id, read_at, created_at)
SELECT ae.user_id,
       'price_drop',
       jsonb_build_object(
           'alert_id', ae.alert_id,
           'price', ae.price,
           'currency', ae.currency,
           'previous_price', ae.previous_price,
           'matched_date', ae.matched_departure_date,
           'origin', pa.origin,
           'destination', pa.destination,
           'depart_date', pa.depart_date,
           'return_date', pa.return_date,
           'target_price', pa.target_price,
           'alert_status', pa.status
       ),
       pa.trip_id,
       ae.read_at,
       ae.occurred_at
FROM alert_events ae
JOIN price_alerts pa ON pa.id = ae.alert_id;

-- +goose Down
-- Drop only the new table; alert_events (the old feed) is left intact so a
-- rollback restores the previous behavior with no data loss.
DROP TABLE notifications;
