-- name: CreateTripShare :one
INSERT INTO trip_shares (chat_id, owner_id, token, role)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetActiveShareByOwnerAndChat :one
-- The owner's current (unrevoked) link of a given role for a chat lineage —
-- share creation is idempotent per (lineage, role), so viewer and editor
-- links coexist.
SELECT * FROM trip_shares
WHERE owner_id = $1 AND chat_id = $2 AND role = $3 AND revoked_at IS NULL
ORDER BY created_at DESC
LIMIT 1;

-- name: GetActiveShareByToken :one
SELECT * FROM trip_shares WHERE token = $1 AND revoked_at IS NULL;

-- name: RevokeSharesByOwnerAndChat :execrows
UPDATE trip_shares SET revoked_at = now()
WHERE owner_id = $1 AND chat_id = $2 AND revoked_at IS NULL;

-- name: GetLatestTripByOwnerAndChat :one
-- The newest version row in a chat lineage — what a share link resolves to.
SELECT * FROM trips
WHERE user_id = $1 AND chat_id = $2
ORDER BY created_at DESC
LIMIT 1;
