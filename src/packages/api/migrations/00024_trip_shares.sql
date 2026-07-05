-- +goose Up
-- Share links for trips. A share binds to the trip's chat_id lineage, not a
-- single trips row: each agent refinement appends a new version row, and the
-- link must always resolve to the latest version. role is 'viewer' today and
-- becomes 'editor' when collaborative editing arrives.
CREATE TABLE trip_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    role TEXT NOT NULL DEFAULT 'viewer',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

CREATE INDEX trip_shares_owner_chat_idx ON trip_shares (owner_id, chat_id);

-- +goose Down
DROP TABLE trip_shares;
