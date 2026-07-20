-- +goose Up
-- Sign in with Apple (specs/apple-sso): second identity provider.
ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
    CHECK (provider IN ('google', 'apple'));

-- +goose Down
DELETE FROM auth_identities WHERE provider = 'apple';
-- Accounts whose ONLY sign-in method was Apple are unreachable afterwards
-- (no password, no remaining identity) — remove them, like 00032's down does
-- for SSO-only users. Apple-linked password/Google accounts survive.
DELETE FROM users u
 WHERE u.password_hash IS NULL
   AND NOT EXISTS (SELECT 1 FROM auth_identities ai WHERE ai.user_id = u.id);
ALTER TABLE auth_identities DROP CONSTRAINT auth_identities_provider_check;
ALTER TABLE auth_identities ADD CONSTRAINT auth_identities_provider_check
    CHECK (provider IN ('google'));
