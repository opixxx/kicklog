CREATE TABLE venues (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name              VARCHAR(100) NOT NULL,
    geo_lat           NUMERIC(9,6) NOT NULL,
    geo_lng           NUMERIC(9,6) NOT NULL,
    address           VARCHAR(255),
    road_address      VARCHAR(255),
    provider          VARCHAR(20),
    provider_place_id VARCHAR(255),
    created_at        TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, name)
);

CREATE UNIQUE INDEX idx_venues_user_provider_place
    ON venues(user_id, provider, provider_place_id)
    WHERE provider IS NOT NULL AND provider_place_id IS NOT NULL;

CREATE INDEX idx_venues_user_id ON venues(user_id);
