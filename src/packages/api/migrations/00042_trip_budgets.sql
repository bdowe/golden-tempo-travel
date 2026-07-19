-- +goose Up
-- Per-trip budget & expense tracking. Honest v1: ONE budget per trip (a target
-- amount + a single currency, default USD — there is no trip-level currency to
-- inherit) plus a flat list of manual expense line-items. Category is a
-- per-expense tag from a bounded set (see budget_handler.go) used only for
-- client-side subtotals; there are NO per-category targets and NO cross-currency
-- summing (no FX) — every expense is assumed to be in the budget's currency.
--
-- Money is DOUBLE PRECISION on purpose (same choice as price_alerts/00029):
-- sqlc emits *float64 for the nullable target_amount and float64 for the
-- NOT NULL expense amount, matching how money is carried elsewhere; cent
-- precision is irrelevant for display and simple summing.
CREATE TABLE trip_budgets (
    id            uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id       uuid             NOT NULL UNIQUE REFERENCES trips(id) ON DELETE CASCADE,
    target_amount double precision,                                -- NULL = no target set yet
    currency      text             NOT NULL DEFAULT 'USD',
    created_at    timestamptz      NOT NULL DEFAULT now(),
    updated_at    timestamptz      NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_trip_budgets_updated_at BEFORE UPDATE ON trip_budgets
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE trip_expenses (
    id          uuid             PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id     uuid             NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    category    text             NOT NULL DEFAULT 'general', -- bounded set, see budget_handler.go
    label       text             NOT NULL,
    amount      double precision NOT NULL,
    position    int              NOT NULL DEFAULT 0,
    auto        boolean          NOT NULL DEFAULT false,    -- reserved: AI-seeded tag (no seeder in v1)
    created_at  timestamptz      NOT NULL DEFAULT now(),
    updated_at  timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_trip_expenses_trip_position ON trip_expenses(trip_id, position);

CREATE TRIGGER trg_trip_expenses_updated_at BEFORE UPDATE ON trip_expenses
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE IF EXISTS trip_expenses;
DROP TABLE IF EXISTS trip_budgets;
