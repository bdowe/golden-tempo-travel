-- name: ListChecklistItemsByTrip :many
SELECT * FROM trip_checklist_items
WHERE trip_id = $1
ORDER BY position ASC, created_at ASC;

-- name: CountChecklistItemsByTrip :one
SELECT count(*) FROM trip_checklist_items WHERE trip_id = $1;

-- name: CreateChecklistItem :one
INSERT INTO trip_checklist_items (trip_id, category, title, position, auto)
VALUES ($1, $2, $3, $4, $5)
RETURNING *;

-- name: UpdateChecklistItem :one
-- Partial update (COALESCE sqlc.narg idiom, see query/booking_todos.sql
-- UpdateBookingTodo). No auto-gating: every row — including AI-seeded auto=true
-- rows — is fully editable by the traveler; that is the whole point of not
-- reusing booking_todos. COALESCE means fields can be overwritten but not
-- cleared to NULL (these columns are all NOT NULL anyway).
UPDATE trip_checklist_items
SET category = COALESCE(sqlc.narg('category'), category),
    title    = COALESCE(sqlc.narg('title'), title),
    checked  = COALESCE(sqlc.narg('checked'), checked),
    position = COALESCE(sqlc.narg('position'), position)
WHERE id = sqlc.arg('id') AND trip_id = sqlc.arg('trip_id')
RETURNING *;

-- name: DeleteChecklistItem :execrows
DELETE FROM trip_checklist_items WHERE id = $1 AND trip_id = $2;
