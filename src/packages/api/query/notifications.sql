-- name: InsertNotification :one
-- Type-agnostic write: the caller supplies the discriminator and a payload bag
-- carrying everything the client needs to render this row without a join.
INSERT INTO notifications (user_id, type, payload, trip_id)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: ListNotificationsByUser :many
-- The whole feed for one user, newest first. No join — every row is
-- self-describing via payload, so any notification type reads the same way.
SELECT * FROM notifications
WHERE user_id = $1
ORDER BY created_at DESC, id DESC
LIMIT $2;

-- name: MarkNotificationsRead :execrows
-- Mark-all is the read model: opening the notification center clears the badge
-- wholesale. No per-notification variant yet.
UPDATE notifications
SET read_at = now()
WHERE user_id = $1 AND read_at IS NULL;

-- name: CountUnreadNotifications :one
SELECT count(*) FROM notifications
WHERE user_id = $1 AND read_at IS NULL;
