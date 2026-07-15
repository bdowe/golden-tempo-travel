-- name: GetAuthIdentity :one
SELECT * FROM auth_identities
WHERE provider = $1 AND provider_user_id = $2;

-- name: CreateAuthIdentity :one
INSERT INTO auth_identities (user_id, provider, provider_user_id, email)
VALUES ($1, $2, $3, $4)
RETURNING *;
