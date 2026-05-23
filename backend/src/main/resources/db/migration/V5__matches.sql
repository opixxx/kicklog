CREATE TABLE matches (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_match_id UUID         NOT NULL,
    venue_id        BIGINT       NOT NULL REFERENCES venues(id),
    played_at       TIMESTAMP WITH TIME ZONE NOT NULL,
    opponent        VARCHAR(100),
    result          VARCHAR(10),
    position        VARCHAR(10),
    goals           INTEGER      NOT NULL DEFAULT 0,
    assists         INTEGER      NOT NULL DEFAULT 0,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, client_match_id)
);

CREATE INDEX idx_matches_user_played_at_id
    ON matches(user_id, played_at DESC, id DESC);

CREATE TABLE quarter_workouts (
    id                    BIGSERIAL PRIMARY KEY,
    match_id              BIGINT       NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    quarter_number        INTEGER      NOT NULL,
    health_kit_workout_id VARCHAR(255) NOT NULL,
    started_at            TIMESTAMP WITH TIME ZONE NOT NULL,
    ended_at              TIMESTAMP WITH TIME ZONE NOT NULL,
    UNIQUE (match_id, quarter_number)
);
