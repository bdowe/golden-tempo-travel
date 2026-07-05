-- +goose Up
-- Signup onboarding quiz: NULL onboarded_at = the user still owes the quiz.
-- Backfill existing users so only accounts created after this see it.
ALTER TABLE users ADD COLUMN onboarded_at timestamptz;
UPDATE users SET onboarded_at = now();

-- +goose Down
ALTER TABLE users DROP COLUMN IF EXISTS onboarded_at;
