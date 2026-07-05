-- +goose Up
-- Ordered membership of pins within a guide. A pin may appear in multiple guides;
-- position gives the guide's narrative order. CASCADE from the guide, RESTRICT
-- would over-constrain the pin, so delete the link when either side goes.
CREATE TABLE local_guide_recommendations (
    guide_id          uuid NOT NULL REFERENCES local_guides(id) ON DELETE CASCADE,
    recommendation_id uuid NOT NULL REFERENCES local_recommendations(id) ON DELETE CASCADE,
    position          int  NOT NULL DEFAULT 0,
    PRIMARY KEY (guide_id, recommendation_id)
);

CREATE INDEX idx_local_guide_recs_guide ON local_guide_recommendations(guide_id, position);

-- +goose Down
DROP TABLE IF EXISTS local_guide_recommendations;
