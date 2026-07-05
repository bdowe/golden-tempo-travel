-- +goose Up
-- A narrative guide authored by a named local — the layer above pins. Prose that
-- ties recommendations together (e.g. "A perfect food day in Trastevere").
CREATE TABLE local_guides (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id      uuid        NOT NULL REFERENCES local_sources(id) ON DELETE RESTRICT,
    title          text        NOT NULL,
    city           text        NOT NULL,
    neighborhood   text,
    body           text        NOT NULL,
    hero_image_url text,
    status         text        NOT NULL DEFAULT 'draft',  -- draft | published | archived
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_local_guides_city_status ON local_guides(city, status);
CREATE INDEX idx_local_guides_source_id ON local_guides(source_id);

CREATE TRIGGER trg_local_guides_updated_at BEFORE UPDATE ON local_guides
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS local_guides;
