-- name: CreateAnalyticsEvent :exec
INSERT INTO analytics_events (user_id, event_type, trip_id, metadata)
VALUES ($1, $2, $3, $4);

-- name: CountEventsByTypeGrouped :many
-- All per-type counts for the metrics window in one round trip (the dashboard
-- previously issued one CountEventsByType query per headline number).
SELECT event_type, count(*)::bigint AS n FROM analytics_events
WHERE created_at >= $1
GROUP BY event_type;

-- name: CountEventsByTypeAndUserSince :one
-- Per-user event count for a trailing window — the free-cap crossing check
-- (specs/free-cap-instrumentation). Counting off analytics_events undercounts
-- in degraded mode; acceptable for a demand signal (see the spec).
SELECT count(*) FROM analytics_events
WHERE event_type = $1 AND user_id = $2 AND created_at >= $3;

-- name: FreeCapWouldHitCounts :many
-- Dashboard rollup for free_cap_would_hit: crossings observed plus the
-- distinct users affected, per cap_kind (plan_runs / active_trips).
SELECT COALESCE(metadata->>'cap_kind', 'unknown')::text AS cap_kind,
       count(*)::bigint AS would_hits,
       count(DISTINCT user_id)::bigint AS users_affected
FROM analytics_events
WHERE event_type = 'free_cap_would_hit' AND created_at >= $1
GROUP BY 1;

-- name: CountActivatedSignups :one
-- Users who registered in the window and have saved at least one trip (ever).
SELECT count(DISTINCT r.user_id) FROM analytics_events r
JOIN analytics_events t ON t.user_id = r.user_id AND t.event_type = 'trip_created'
WHERE r.event_type = 'user_registered' AND r.created_at >= $1;

-- name: CountTripsWithBookingClick :one
SELECT count(DISTINCT trip_id) FROM analytics_events
WHERE event_type = 'booking_link_clicked' AND trip_id IS NOT NULL AND created_at >= $1;

-- name: BookingClicksByProvider :many
-- provider is client-supplied (sanitized at ingest since Wave 7, but older
-- rows predate that): left(..., 64) + LIMIT 20 bound the admin dashboard's
-- rollup against arbitrary historical values.
SELECT COALESCE(left(metadata->>'provider', 64), 'unknown')::text AS provider, count(*) AS clicks
FROM analytics_events
WHERE event_type = 'booking_link_clicked' AND created_at >= $1
GROUP BY 1 ORDER BY clicks DESC, provider
LIMIT 20;

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
--   second_trip_retention      — users whose trip_created events span >= 2
--                                DISTINCT trip lineages (COALESCE(chat_id,
--                                id) — the My Trips grouping) with first
--                                creations >= 7 days apart (the business
--                                model's "returned for a second trip" signal;
--                                max-min >= 7 days implies >= 2 lineages).
--                                Grouping by lineage keeps re-finalizing one
--                                chat — a version save, which also emits
--                                trip_created — from counting as a second
--                                trip. Trade-off: the trips join drops events
--                                whose trip row was later deleted, a slight
--                                undercount (vs. the per-event overcount it
--                                replaces); acceptable until trip deletion is
--                                a real flow.
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
     SELECT l.user_id FROM (
       SELECT c.user_id, min(c.created_at) AS first_at
       FROM analytics_events c
       JOIN trips tr ON tr.id = c.trip_id
       WHERE c.event_type = 'trip_created' AND c.user_id IS NOT NULL
         AND c.created_at >= $1
       GROUP BY c.user_id, COALESCE(tr.chat_id, tr.id::text)
     ) l
     GROUP BY l.user_id
     HAVING max(l.first_at) - min(l.first_at) >= interval '7 days'
   ) t)::bigint AS second_trip_retention;
