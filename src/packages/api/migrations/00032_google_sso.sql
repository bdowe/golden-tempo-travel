-- +goose Up
-- Google SSO (specs/google-sso): external identities linked to users, plus
-- SSO-only accounts (no password) and a short-lived 'sso' handoff token purpose.
CREATE TABLE auth_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('google')),
    provider_user_id TEXT NOT NULL,
    email TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_user_id)
);

CREATE INDEX auth_identities_user_idx ON auth_identities (user_id);

-- Accounts created via Google have no password until they set one via reset.
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

ALTER TABLE email_tokens DROP CONSTRAINT email_tokens_purpose_check;
ALTER TABLE email_tokens ADD CONSTRAINT email_tokens_purpose_check
    CHECK (purpose IN ('verify', 'reset', 'sso'));

-- +goose Down
ALTER TABLE email_tokens DROP CONSTRAINT email_tokens_purpose_check;
DELETE FROM email_tokens WHERE purpose = 'sso';
ALTER TABLE email_tokens ADD CONSTRAINT email_tokens_purpose_check
    CHECK (purpose IN ('verify', 'reset'));

-- SSO-only accounts cannot survive the NOT NULL restore.
DELETE FROM users WHERE password_hash IS NULL;
ALTER TABLE users ALTER COLUMN password_hash SET NOT NULL;

DROP TABLE auth_identities;
