-- +goose Up
-- Provenance/audit trail for ingestion: the raw research material (interview
-- transcript, notes, voice-memo text) an AI extraction ran against. Retained for
-- consent/licensing traceability and to re-run extraction if the model improves.
CREATE TABLE local_source_material (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id  uuid        NOT NULL REFERENCES local_sources(id) ON DELETE RESTRICT,
    kind       text        NOT NULL,       -- transcript | notes | voice_memo
    raw_text   text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_local_source_material_source ON local_source_material(source_id);

-- +goose Down
DROP TABLE IF EXISTS local_source_material;
