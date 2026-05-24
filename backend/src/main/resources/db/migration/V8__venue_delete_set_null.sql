ALTER TABLE matches
    DROP CONSTRAINT matches_venue_id_fkey;

ALTER TABLE matches
    ALTER COLUMN venue_id DROP NOT NULL;

ALTER TABLE matches
    ADD CONSTRAINT matches_venue_id_fkey
        FOREIGN KEY (venue_id) REFERENCES venues(id) ON DELETE SET NULL;
