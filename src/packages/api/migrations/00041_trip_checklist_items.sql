-- +goose Up
-- A lightweight per-trip packing/prep checklist. Deliberately its OWN table,
-- NOT booking_todos: that table's client itinerary-sync reaper deletes auto=true
-- rows not in the current derived set and hard-gates edits/deletes to auto=false,
-- which would silently eat AI-seeded packing rows and freeze them read-only.
-- Here auto=true only tags an AI-seeded row for display; the traveler edits,
-- toggles, and deletes every row freely (no auto-gating anywhere).
CREATE TABLE trip_checklist_items (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id     uuid        NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    category    text        NOT NULL DEFAULT 'general', -- clothing | documents | electronics | health | general (free text; client groups)
    title       text        NOT NULL,
    checked     boolean     NOT NULL DEFAULT false,
    position    int         NOT NULL DEFAULT 0,
    auto        boolean     NOT NULL DEFAULT false,     -- true = AI-seeded
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_trip_checklist_items_trip_position ON trip_checklist_items(trip_id, position);

CREATE TRIGGER trg_trip_checklist_items_updated_at BEFORE UPDATE ON trip_checklist_items
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS trip_checklist_items;
