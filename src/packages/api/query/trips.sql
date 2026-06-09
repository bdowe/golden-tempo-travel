-- name: CreateTrip :one
INSERT INTO trips (user_id, title, status, chat_id, summary)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: CreateItineraryItem :one
INSERT INTO itinerary_items (trip_id, position, name, place_id, address, latitude, longitude, category, time_of_day, city, day_trip_from)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
RETURNING *;

-- name: ListTripsByOwner :many
SELECT * FROM trips WHERE user_id = $1 ORDER BY created_at DESC;

-- name: ListLatestTripsByOwner :many
-- One row per chat group (latest version), with how many versions exist.
-- Legacy trips with NULL chat_id stand alone (grouped by their own id).
SELECT * FROM (
  SELECT DISTINCT ON (COALESCE(chat_id, id::text))
         id, user_id, created_at, updated_at, title, start_date, end_date, status, chat_id,
         count(*) OVER (PARTITION BY COALESCE(chat_id, id::text)) AS version_count
  FROM trips WHERE user_id = $1
  ORDER BY COALESCE(chat_id, id::text), created_at DESC
) latest ORDER BY created_at DESC;

-- name: ListTripVersionsByChat :many
SELECT * FROM trips WHERE user_id = $1 AND chat_id = $2 ORDER BY created_at DESC;

-- name: GetTripByIDAndOwner :one
SELECT * FROM trips WHERE id = $1 AND user_id = $2;

-- name: GetItineraryItemsByTrip :many
SELECT * FROM itinerary_items WHERE trip_id = $1 ORDER BY position ASC;

-- name: UpdateTrip :one
UPDATE trips
SET title      = COALESCE(sqlc.narg('title'), title),
    start_date = COALESCE(sqlc.narg('start_date'), start_date),
    end_date   = COALESCE(sqlc.narg('end_date'), end_date),
    status     = COALESCE(sqlc.narg('status'), status),
    chat_id    = COALESCE(sqlc.narg('chat_id'), chat_id)
WHERE id = sqlc.arg('id') AND user_id = sqlc.arg('user_id')
RETURNING *;

-- name: DeleteTrip :execrows
-- Deletes the trip and, when it belongs to a chat group, all its versions.
-- Legacy trips (chat_id NULL) match only by id, so a single row is removed.
DELETE FROM trips t
WHERE t.user_id = sqlc.arg('user_id')
  AND (
    t.id = sqlc.arg('id')
    OR t.chat_id = (
      SELECT chat_id FROM trips
      WHERE id = sqlc.arg('id') AND user_id = sqlc.arg('user_id') AND chat_id IS NOT NULL
    )
  );
