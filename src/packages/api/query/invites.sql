-- name: CreateTripInvite :one
INSERT INTO trip_invites (chat_id, owner_id, email, role, token_hash, expires_at)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING *;

-- name: ListPendingInvitesByOwnerAndChat :many
SELECT * FROM trip_invites
WHERE owner_id = $1 AND chat_id = $2
  AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now()
ORDER BY created_at ASC;

-- name: RevokePendingInviteByEmail :execrows
-- Reissue path: void the previous invite to this address before minting a
-- fresh token (mirror of issueEmailToken's invalidate-then-create).
UPDATE trip_invites SET revoked_at = now()
WHERE owner_id = $1 AND chat_id = $2 AND email = $3
  AND accepted_at IS NULL AND revoked_at IS NULL;

-- name: RevokeTripInviteByID :execrows
UPDATE trip_invites SET revoked_at = now()
WHERE id = $1 AND owner_id = $2 AND accepted_at IS NULL AND revoked_at IS NULL;

-- name: GetValidInviteByTokenHash :one
SELECT * FROM trip_invites
WHERE token_hash = $1 AND accepted_at IS NULL AND revoked_at IS NULL
  AND expires_at > now();

-- name: GetInviteByTokenHash :one
-- Any state — lets accept be idempotent for the user who already redeemed.
SELECT * FROM trip_invites WHERE token_hash = $1;

-- name: AcceptTripInvite :execrows
-- Race-safe single use: the WHERE re-checks pending state, so of two
-- concurrent accepts only one row-update wins.
UPDATE trip_invites SET accepted_at = now(), accepted_by = $2
WHERE id = $1 AND accepted_at IS NULL AND revoked_at IS NULL
  AND expires_at > now();

-- name: CountPendingInvitesByOwnerAndChat :one
SELECT count(*) FROM trip_invites
WHERE owner_id = $1 AND chat_id = $2
  AND accepted_at IS NULL AND revoked_at IS NULL AND expires_at > now();
