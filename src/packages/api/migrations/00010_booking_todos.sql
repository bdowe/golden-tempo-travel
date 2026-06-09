-- +goose Up
CREATE TABLE booking_todos (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id     uuid        NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    kind        text        NOT NULL,            -- stay | transport | other
    todo_key    text        NOT NULL,            -- stable natural key, e.g. "stay:lisbon" / "transport:lisbon>porto"
    title       text        NOT NULL,            -- "Lisbon → Porto" / "Stay in Porto"
    subtitle    text,                            -- "Mar 14 · 1 adult"
    provider    text,                            -- airbnb | google_flights (drives card icon/label)
    search_url  text,
    depart_date date,                            -- transport depart / stay check-in
    return_date date,                            -- stay check-out (null for transport)
    booked      boolean     NOT NULL DEFAULT false,
    auto        boolean     NOT NULL DEFAULT true, -- false = user-added custom
    position    int         NOT NULL DEFAULT 0,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_booking_todos_trip_key ON booking_todos(trip_id, todo_key);
CREATE INDEX idx_booking_todos_trip_id ON booking_todos(trip_id);

CREATE TRIGGER trg_booking_todos_updated_at BEFORE UPDATE ON booking_todos
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS booking_todos;
