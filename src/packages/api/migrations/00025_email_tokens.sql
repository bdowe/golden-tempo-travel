-- +goose Up
-- Single-use tokens for email verification and password reset. Only the
-- sha256 of the token is stored — unlike session tokens these transit email.
CREATE TABLE email_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purpose TEXT NOT NULL CHECK (purpose IN ('verify', 'reset')),
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX email_tokens_user_purpose_idx ON email_tokens (user_id, purpose);

ALTER TABLE users ADD COLUMN email_verified_at TIMESTAMPTZ;

-- +goose Down
ALTER TABLE users DROP COLUMN email_verified_at;
DROP TABLE email_tokens;
