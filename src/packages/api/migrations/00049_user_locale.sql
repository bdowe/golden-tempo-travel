-- +goose Up
-- Preferred UI/content language for this account, as a base language subtag
-- ('en' | 'es'). NULL = never resolved: accounts that predate i18n, or a client
-- that has not synced yet. Every reader falls back to 'en', so NULL is safe.
--
-- This lives on users rather than traveler_preferences on purpose. Locale is
-- app configuration, not travel taste: the background email jobs
-- (reengagement_checker.go, price_alert_checker.go) run with no request context
-- and already read the users row, so joining it costs nothing here and a LEFT
-- JOIN there — and, critically, the /plan agent's save_preferences tool writes
-- traveler_preferences, which would let the model overwrite the user's language.
-- Same shape as 00044_email_prefs.sql.
ALTER TABLE users ADD COLUMN locale TEXT;

-- +goose Down
ALTER TABLE users DROP COLUMN locale;
