ALTER TABLE matches
    ADD COLUMN total_distance_m INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN max_speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN sprint_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN avg_heart_rate INTEGER NOT NULL DEFAULT 0;

ALTER TABLE quarter_workouts
    ADD COLUMN duration_seconds INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN distance_m INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN avg_speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN avg_heart_rate INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN max_heart_rate INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN sprint_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN active_energy_kcal INTEGER NOT NULL DEFAULT 0;

CREATE INDEX idx_matches_user_played_at
    ON matches(user_id, played_at);
