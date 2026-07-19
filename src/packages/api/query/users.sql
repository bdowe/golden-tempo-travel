-- name: CreateUser :one
INSERT INTO users (email, password_hash, display_name)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = $1;

-- name: GetUserByID :one
SELECT * FROM users WHERE id = $1;

-- name: MarkUserOnboarded :one
UPDATE users SET onboarded_at = COALESCE(onboarded_at, now())
WHERE id = $1
RETURNING *;

-- name: UpdateUserPassword :exec
UPDATE users SET password_hash = $2 WHERE id = $1;

-- name: MarkUserEmailVerified :exec
UPDATE users SET email_verified_at = COALESCE(email_verified_at, now())
WHERE id = $1;

-- name: UpdateUserDisplayName :one
UPDATE users SET display_name = $2 WHERE id = $1
RETURNING *;

-- name: SetUserEmailOptOut :one
-- Category-partial opt-out setter: a NULL arg leaves that flag untouched, so a
-- single query handles reminders-only, nudges-only, or all-at-once. Used by
-- both the one-click unsubscribe link and the account-settings PATCH.
UPDATE users SET
    reminders_opt_out = COALESCE(sqlc.narg('reminders_opt_out'), reminders_opt_out),
    nudges_opt_out    = COALESCE(sqlc.narg('nudges_opt_out'), nudges_opt_out)
WHERE id = sqlc.arg('id')
RETURNING *;

-- name: DeleteUser :execrows
DELETE FROM users WHERE id = $1;
