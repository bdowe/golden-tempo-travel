-- +goose Up
-- Explicit collaborator membership for shared trips. A signed-in user becomes
-- a collaborator by redeeming an editor-role share token; membership is state,
-- the token is only the capability to join (revoking a link stops new joins
-- but does not evict existing collaborators). Lineage-scoped (owner_id +
-- chat_id) like trip_shares, so membership survives agent version appends.
CREATE TABLE trip_collaborators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chat_id TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'editor',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX trip_collaborators_active_uniq
    ON trip_collaborators (owner_id, chat_id, user_id) WHERE revoked_at IS NULL;
CREATE INDEX trip_collaborators_user_idx ON trip_collaborators (user_id);

-- +goose Down
DROP TABLE trip_collaborators;
