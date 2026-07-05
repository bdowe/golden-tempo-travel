-- +goose Up
-- The atomic unit: a place-level pin carrying a local's tip/quote. Coordinates
-- stay NULL until geocoded/verified via Google Places; publish is blocked while
-- they are NULL. ON DELETE RESTRICT so a cited source can never be orphaned.
CREATE TABLE local_recommendations (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id      uuid        NOT NULL REFERENCES local_sources(id) ON DELETE RESTRICT,
    city           text        NOT NULL,
    neighborhood   text,
    name           text        NOT NULL,
    place_id       text,                    -- Google Places id, filled on verify
    address        text,
    latitude       double precision,        -- NULL until geocoded
    longitude      double precision,        -- NULL until geocoded
    category       text,                    -- reuse attraction | restaurant
    tip            text,                    -- the actionable advice
    quote          text,                    -- verbatim local voice
    tags           text[]      NOT NULL DEFAULT '{}',
    status         text        NOT NULL DEFAULT 'draft',  -- draft | published | archived
    place_verified boolean     NOT NULL DEFAULT false,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_local_recommendations_city_status ON local_recommendations(city, status);
CREATE INDEX idx_local_recommendations_status ON local_recommendations(status);
CREATE INDEX idx_local_recommendations_source_id ON local_recommendations(source_id);

CREATE TRIGGER trg_local_recommendations_updated_at BEFORE UPDATE ON local_recommendations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS local_recommendations;
