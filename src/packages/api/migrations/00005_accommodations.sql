-- +goose Up
CREATE TABLE accommodations (
    id         uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id    uuid             NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    name       text             NOT NULL,
    provider   text,                              -- airbnb | booking | other
    url        text,
    address    text,
    latitude   double precision,
    longitude  double precision,
    check_in   date,
    check_out  date,
    price_note text,
    created_at timestamptz      NOT NULL DEFAULT now(),
    updated_at timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_accommodations_trip_id ON accommodations(trip_id);

CREATE TRIGGER trg_accommodations_updated_at BEFORE UPDATE ON accommodations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS accommodations;
