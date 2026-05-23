-- ============================================
-- Auth refresh rotation policy
-- ============================================
-- V2 introduced Kakao login and refresh_tokens. This migration aligns the
-- placeholder auth schema with ADR-0003 D7.1: access 15m + refresh 30d + rotation.

ALTER TABLE users DROP COLUMN IF EXISTS apple_user_id;
ALTER TABLE users DROP COLUMN IF EXISTS username;
ALTER TABLE users ALTER COLUMN display_name TYPE VARCHAR(50);

ALTER TABLE oauth_identities RENAME COLUMN created_at TO linked_at;
ALTER TABLE oauth_identities
    ADD CONSTRAINT chk_oauth_provider CHECK (provider IN ('apple', 'kakao'));

ALTER TABLE oauth_identities DROP CONSTRAINT IF EXISTS oauth_identities_user_id_fkey;
ALTER TABLE oauth_identities
    ADD CONSTRAINT oauth_identities_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE refresh_tokens ADD COLUMN rotated_to_jti UUID;
ALTER TABLE refresh_tokens ADD COLUMN device_info VARCHAR(255);
ALTER TABLE refresh_tokens ADD COLUMN last_used_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE refresh_tokens DROP CONSTRAINT IF EXISTS refresh_tokens_user_id_fkey;
ALTER TABLE refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

DROP INDEX IF EXISTS idx_refresh_tokens_user_id;
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;
