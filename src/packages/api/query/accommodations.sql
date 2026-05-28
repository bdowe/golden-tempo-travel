-- name: CreateAccommodation :one
INSERT INTO accommodations (trip_id, name, provider, url, address, latitude, longitude, check_in, check_out, price_note)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
RETURNING *;

-- name: ListAccommodationsByTrip :many
SELECT * FROM accommodations WHERE trip_id = $1 ORDER BY check_in ASC NULLS LAST, created_at ASC;

-- name: DeleteAccommodation :execrows
DELETE FROM accommodations WHERE id = $1 AND trip_id = $2;
