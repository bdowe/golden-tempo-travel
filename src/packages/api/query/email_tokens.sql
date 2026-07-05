-- name: CreateEmailToken :one
INSERT INTO email_tokens (user_id, purpose, token_hash, expires_at)
VALUES ($1, $2, $3, $4)
RETURNING *;

-- name: GetValidEmailToken :one
SELECT * FROM email_tokens
WHERE token_hash = $1 AND purpose = $2 AND used_at IS NULL AND expires_at > now();

-- name: MarkEmailTokenUsed :exec
UPDATE email_tokens SET used_at = now() WHERE id = $1;

-- name: InvalidateEmailTokens :exec
-- Voids a user's outstanding tokens for a purpose (issuing a new reset link
-- kills the previous one).
UPDATE email_tokens SET used_at = now()
WHERE user_id = $1 AND purpose = $2 AND used_at IS NULL;
