-- ============================================
-- Auth schema: OAuth identities and JWT sessions
-- ============================================
-- V1 was an ADR placeholder. MVP auth uses provider identities and refresh-token sessions.

DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    id              BIGSERIAL PRIMARY KEY,
    display_name    VARCHAR(50)  NOT NULL,
    email           VARCHAR(255),
    hide_heart_rate BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP WITH TIME ZONE  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE  NOT NULL DEFAULT NOW(),
    deleted_at      TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_display_name ON users(display_name) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NOT NULL;

CREATE TABLE oauth_identities (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider          VARCHAR(20)  NOT NULL,
    provider_user_id  VARCHAR(255) NOT NULL,
    email             VARCHAR(255),
    linked_at         TIMESTAMP WITH TIME ZONE  NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_user_id),
    CHECK (provider IN ('apple', 'kakao'))
);

CREATE INDEX idx_oauth_identities_user_id ON oauth_identities(user_id);

CREATE TABLE refresh_tokens (
    jti             UUID         PRIMARY KEY,
    user_id         BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at      TIMESTAMP WITH TIME ZONE  NOT NULL,
    revoked_at      TIMESTAMP WITH TIME ZONE,
    rotated_to_jti  UUID,
    device_info     VARCHAR(255),
    created_at      TIMESTAMP WITH TIME ZONE  NOT NULL DEFAULT NOW(),
    last_used_at    TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_refresh_tokens_expires_at ON refresh_tokens(expires_at) WHERE revoked_at IS NULL;
