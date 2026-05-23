CREATE TABLE friendships (
    id              BIGSERIAL PRIMARY KEY,
    user_low_id     BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_high_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL,
    initiated_by_id BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    accepted_at     TIMESTAMP WITH TIME ZONE,
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (user_low_id, user_high_id),
    CHECK (user_low_id < user_high_id),
    CHECK (status IN ('PENDING', 'ACCEPTED'))
);

CREATE INDEX idx_friendships_low_status ON friendships(user_low_id, status);
CREATE INDEX idx_friendships_high_status ON friendships(user_high_id, status);

CREATE TABLE friend_invitations (
    id         BIGSERIAL PRIMARY KEY,
    inviter_id BIGINT     NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token      VARCHAR(8) NOT NULL UNIQUE,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    use_count  INTEGER    NOT NULL DEFAULT 0,
    revoked_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_friend_invitations_inviter
    ON friend_invitations(inviter_id)
    WHERE revoked_at IS NULL;

CREATE INDEX idx_friend_invitations_token ON friend_invitations(token);
