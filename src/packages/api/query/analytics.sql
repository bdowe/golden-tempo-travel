-- name: CreateAnalyticsEvent :exec
INSERT INTO analytics_events (user_id, event_type, trip_id, metadata)
VALUES ($1, $2, $3, $4);

-- name: CountEventsByTypeGrouped :many
-- All per-type counts for the metrics window in one round trip (the dashboard
-- previously issued one CountEventsByType query per headline number).
SELECT event_type, count(*)::bigint AS n FROM analytics_events
WHERE created_at >= $1
GROUP BY event_type;

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
-- Sessions + token spend from plan_session_completed metadata, plus the
-- anonymous split and agent-loop cap hits (all filters over the same
-- completed-session denominator, folded into one round trip).
SELECT count(*) AS sessions,
       count(*) FILTER (WHERE user_id IS NULL)::bigint AS anonymous_sessions,
       count(*) FILTER (WHERE (metadata->>'max_iterations_hit')::boolean)::bigint AS agent_loop_cap_hits,
       COALESCE(sum((metadata->>'input_tokens')::bigint), 0)::bigint AS input_tokens,
       COALESCE(sum((metadata->>'output_tokens')::bigint), 0)::bigint AS output_tokens,
       COALESCE(sum((metadata->>'cache_read_tokens')::bigint), 0)::bigint AS cache_read_tokens,
       COALESCE(sum((metadata->>'cache_creation_tokens')::bigint), 0)::bigint AS cache_creation_tokens
FROM analytics_events
WHERE event_type = 'plan_session_completed' AND created_at >= $1;

-- name: UserEngagementCounts :one
-- The three user-level engagement numbers in one round trip.
-- user_id IS NOT NULL everywhere: anonymous sessions must not group into a
-- phantom user.
--   active_users               — MAU: distinct users who started >= 1 planning
--                                session in the window.
--   session_frequency_returning — users with planning sessions on >= 2 distinct
--                                days (a session-frequency proxy; NOT trip
--                                retention).
--   second_trip_retention      — users with >= 2 trip_created events >= 7 days
--                                apart (the business model's "returned for a
--                                second trip" signal; max-min >= 7 days implies
--                                >= 2 events).
SELECT
  (SELECT count(DISTINCT a.user_id) FROM analytics_events a
   WHERE a.event_type = 'plan_session_started' AND a.user_id IS NOT NULL
     AND a.created_at >= $1)::bigint AS active_users,
  (SELECT count(*) FROM (
     SELECT b.user_id FROM analytics_events b
     WHERE b.event_type = 'plan_session_started' AND b.user_id IS NOT NULL
       AND b.created_at >= $1
     GROUP BY b.user_id
     HAVING count(DISTINCT date(b.created_at)) >= 2
   ) s)::bigint AS session_frequency_returning,
  (SELECT count(*) FROM (
     SELECT c.user_id FROM analytics_events c
     WHERE c.event_type = 'trip_created' AND c.user_id IS NOT NULL
       AND c.created_at >= $1
     GROUP BY c.user_id
     HAVING max(c.created_at) - min(c.created_at) >= interval '7 days'
   ) t)::bigint AS second_trip_retention;
