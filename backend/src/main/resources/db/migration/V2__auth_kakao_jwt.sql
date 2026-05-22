ALTER TABLE users
    ALTER COLUMN apple_user_id DROP NOT NULL;

ALTER TABLE users
    ADD COLUMN email VARCHAR(255);

ALTER TABLE users
    ADD COLUMN deleted_at TIMESTAMPTZ;

CREATE TABLE oauth_identities (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT       NOT NULL REFERENCES users(id),
    provider         VARCHAR(20)  NOT NULL,
    provider_user_id VARCHAR(255) NOT NULL,
    email            VARCHAR(255),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    UNIQUE (provider, provider_user_id)
);

CREATE INDEX idx_oauth_identities_user_id ON oauth_identities(user_id);

CREATE TABLE refresh_tokens (
    jti        UUID PRIMARY KEY,
    user_id    BIGINT      NOT NULL REFERENCES users(id),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
