-- +goose Up
-- One global preference profile per user (1:1).
CREATE TABLE traveler_preferences (
    user_id    uuid        PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    budget     text,                              -- budget | mid | luxury
    pace       text,                              -- relaxed | balanced | packed
    interests  text[]      NOT NULL DEFAULT '{}', -- free theme tags
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_traveler_preferences_updated_at BEFORE UPDATE ON traveler_preferences
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS traveler_preferences;
