-- name: ListBookingTodosByTrip :many
SELECT * FROM booking_todos WHERE trip_id = $1 ORDER BY position ASC, created_at ASC;

-- name: UpsertBookingTodo :one
INSERT INTO booking_todos (trip_id, kind, todo_key, title, subtitle, provider, search_url, depart_date, return_date, position, auto)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, true)
ON CONFLICT (trip_id, todo_key) DO UPDATE SET
    kind = EXCLUDED.kind,
    title = EXCLUDED.title,
    subtitle = EXCLUDED.subtitle,
    provider = EXCLUDED.provider,
    search_url = EXCLUDED.search_url,
    depart_date = EXCLUDED.depart_date,
    return_date = EXCLUDED.return_date,
    position = EXCLUDED.position
RETURNING *;

-- name: DeleteStaleAutoBookingTodos :execrows
DELETE FROM booking_todos
WHERE trip_id = $1 AND auto = true AND todo_key <> ALL(@keys::text[]);

-- name: CreateBookingTodo :one
INSERT INTO booking_todos (trip_id, kind, todo_key, title, subtitle, provider, search_url, depart_date, return_date, position, auto)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, false)
RETURNING *;

-- name: SetBookingTodoBooked :one
UPDATE booking_todos SET booked = $3 WHERE id = $1 AND trip_id = $2 RETURNING *;

-- name: DeleteBookingTodo :execrows
DELETE FROM booking_todos WHERE id = $1 AND trip_id = $2;
