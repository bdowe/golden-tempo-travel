-- +goose Up
-- Flesh out the baseline users table with identity fields and add sessions.
-- email is stored lowercased (enforced by the app + CHECK); uniqueness is
-- case-insensitive as a result.
ALTER TABLE users
    ADD COLUMN email         text NOT NULL UNIQUE CHECK (email = lower(email)),
    ADD COLUMN password_hash text NOT NULL,
    ADD COLUMN display_name  text;

CREATE TABLE sessions (
    id         text        PRIMARY KEY,            -- opaque random token (crypto/rand hex)
    user_id    uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);

-- +goose Down
DROP TABLE IF EXISTS sessions;
ALTER TABLE users
    DROP COLUMN IF EXISTS email,
    DROP COLUMN IF EXISTS password_hash,
    DROP COLUMN IF EXISTS display_name;
