-- +goose Up
-- Re-engagement dedup ledger (Wave 16). The trip-reminder checker (3-days-out +
-- day-of) is idempotent across ticks by recording each (user, trip lineage,
-- kind) it has sent. trip_lineage_key is COALESCE(chat_id, id::text) — the same
-- lineage key ListLatestTripsByOwner groups on — so the whole version chain of
-- one trip reminds once per kind, not once per saved version. No FK to trips:
-- the lineage key is a text snapshot that survives a trip (or a whole lineage)
-- being deleted, so a re-created trip can't accidentally re-fire an old kind.
CREATE TABLE reminder_sends (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trip_lineage_key TEXT NOT NULL,
    kind TEXT NOT NULL,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, trip_lineage_key, kind)
);

-- Weekly-nudge dedup is a single per-user timestamp rather than a ledger row:
-- the nudge fires at most once a week, so "last time we nudged" is all the guard
-- needs (NULL = never nudged). Self-pacing regardless of the checker's tick.
ALTER TABLE users ADD COLUMN last_weekly_nudge_at TIMESTAMPTZ;

-- +goose Down
ALTER TABLE users DROP COLUMN last_weekly_nudge_at;
DROP TABLE reminder_sends;
