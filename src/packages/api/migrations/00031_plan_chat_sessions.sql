-- +goose Up
-- Resumable plan conversations (specs/continue-where-you-left-off): one row
-- per (user, chat), upserted wholesale each /plan turn. messages holds the
-- client-format wire history ([{"role","content"}]) and summary the running
-- compaction summary — together exactly what a live client would resend, so
-- a resume is indistinguishable from a session that never left. A chat
-- "graduates" (stops being resumable) when a trip with its chat_id exists;
-- that is a read-time filter, not a column, so no writer here races the
-- create_itinerary path.
CREATE TABLE plan_chat_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    chat_id TEXT NOT NULL,
    title TEXT NOT NULL,
    preview TEXT NOT NULL DEFAULT '',
    summary TEXT NOT NULL DEFAULT '',
    messages JSONB NOT NULL,
    message_count INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, chat_id)
);

CREATE INDEX plan_chat_sessions_user_recent_idx
    ON plan_chat_sessions (user_id, updated_at DESC);

-- +goose Down
DROP TABLE plan_chat_sessions;
