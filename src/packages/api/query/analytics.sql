-- name: CreateAnalyticsEvent :exec
INSERT INTO analytics_events (user_id, event_type, trip_id, metadata)
VALUES ($1, $2, $3, $4);

-- name: CountEventsByType :one
SELECT count(*) FROM analytics_events
WHERE event_type = $1 AND created_at >= $2;

-- name: CountActivatedSignups :one
-- Users who registered in the window and have saved at least one trip (ever).
SELECT count(DISTINCT r.user_id) FROM analytics_events r
JOIN analytics_events t ON t.user_id = r.user_id AND t.event_type = 'trip_created'
WHERE r.event_type = 'user_registered' AND r.created_at >= $1;

-- name: CountTripsWithBookingClick :one
SELECT count(DISTINCT trip_id) FROM analytics_events
WHERE event_type = 'booking_link_clicked' AND trip_id IS NOT NULL AND created_at >= $1;

-- name: BookingClicksByProvider :many
SELECT COALESCE(metadata->>'provider', 'unknown')::text AS provider, count(*) AS clicks
FROM analytics_events
WHERE event_type = 'booking_link_clicked' AND created_at >= $1
GROUP BY 1 ORDER BY clicks DESC;

-- name: PlanSessionTotals :one
-- Sessions + token spend from plan_session_completed metadata.
SELECT count(*) AS sessions,
       COALESCE(sum((metadata->>'input_tokens')::bigint), 0)::bigint AS input_tokens,
       COALESCE(sum((metadata->>'output_tokens')::bigint), 0)::bigint AS output_tokens,
       COALESCE(sum((metadata->>'cache_read_tokens')::bigint), 0)::bigint AS cache_read_tokens,
       COALESCE(sum((metadata->>'cache_creation_tokens')::bigint), 0)::bigint AS cache_creation_tokens
FROM analytics_events
WHERE event_type = 'plan_session_completed' AND created_at >= $1;

-- name: CountAnonymousPlanSessions :one
SELECT count(*) FROM analytics_events
WHERE event_type = 'plan_session_started' AND user_id IS NULL AND created_at >= $1;

-- name: CountPlanCapHits :one
-- Sessions that hit the agent-loop iteration cap (free-tier pressure signal).
SELECT count(*) FROM analytics_events
WHERE event_type = 'plan_session_completed'
  AND (metadata->>'max_iterations_hit')::boolean
  AND created_at >= $1;

-- name: CountReturningUsers :one
-- Users with planning sessions on at least two distinct days in the window.
-- user_id IS NOT NULL: anonymous sessions must not group into a phantom user.
SELECT count(*) FROM (
  SELECT user_id FROM analytics_events
  WHERE event_type = 'plan_session_started' AND user_id IS NOT NULL AND created_at >= $1
  GROUP BY user_id
  HAVING count(DISTINCT date(created_at)) >= 2
) returning_users;
