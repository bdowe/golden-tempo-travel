-- +goose Up
-- Email invites for co-planning (specs/invite-by-email). Lineage-scoped
-- (owner_id + chat_id) like trip_shares/trip_collaborators. The token
-- transits email, so only its sha256 is stored (same rationale as
-- email_tokens); unlike share links an invite is single-use, TTL'd, bound to
-- an address, and individually revocable. accepted_by is recorded separately
-- from email on purpose: with SSO the redeemer's account email may differ
-- from the invited address, and the token is the capability.
CREATE TABLE trip_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'editor',
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    accepted_by UUID REFERENCES users(id) ON DELETE SET NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- At most one live invite per (lineage, address); re-inviting revokes the
-- old row first.
CREATE UNIQUE INDEX trip_invites_pending_uniq
    ON trip_invites (owner_id, chat_id, email)
    WHERE accepted_at IS NULL AND revoked_at IS NULL;
CREATE INDEX trip_invites_owner_chat_idx ON trip_invites (owner_id, chat_id);

-- +goose Down
DROP TABLE trip_invites;
