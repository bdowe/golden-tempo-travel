-- +goose Up
-- A named local whose takes power the "legit info you can't google" content.
-- The attribution root: every recommendation and guide references one source.
CREATE TABLE local_sources (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text        NOT NULL,
    bio         text,                       -- short blurb shown on cards
    photo_url   text,                       -- the local's face
    location    text,                       -- where they're based / know best
    expertise   text,                       -- e.g. "food & wine", "nightlife"
    credibility text,                       -- why we trust them (chef, guide, 20yr resident)
    consent_ref text,                       -- reference to recorded consent/release; gates publish
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_local_sources_updated_at BEFORE UPDATE ON local_sources
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS local_sources;
