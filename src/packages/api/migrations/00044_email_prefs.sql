-- +goose Up
-- Per-category email opt-out flags. Both marketing-ish streams default to
-- opted-IN (false = still receiving), each independently unsubscribable via a
-- signed one-click link (RFC 8058 List-Unsubscribe). A weekly nudge legally
-- needs opt-out; transactional mail (verify/reset) is not gated by these.
ALTER TABLE users
    ADD COLUMN reminders_opt_out BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN nudges_opt_out    BOOLEAN NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE users
    DROP COLUMN reminders_opt_out,
    DROP COLUMN nudges_opt_out;
