package main

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"travel-route-planner/store"
)

func TestAdminRoutesRequireAdmin(t *testing.T) {
	resetDB(t)
	_, userToken := createTestUser(t, "civilian@example.com")

	paths := []string{
		"/api/v1/admin/metrics",
		"/api/v1/admin/local/sources",
		"/api/v1/admin/local/coverage",
		"/api/v1/trips/versions",
	}
	for _, p := range paths {
		if rec := doJSON(t, "GET", p, userToken, nil); rec.Code != http.StatusForbidden {
			t.Fatalf("non-admin GET %s = %d, want 403", p, rec.Code)
		}
		if rec := doJSON(t, "GET", p, "", nil); rec.Code != http.StatusUnauthorized {
			t.Fatalf("anonymous GET %s = %d, want 401", p, rec.Code)
		}
	}
}

func TestAdminMetricsForAdmin(t *testing.T) {
	resetDB(t)
	admin, adminToken := createTestUser(t, "admin@example.com")
	makeAdmin(t, admin.ID)

	rec := doJSON(t, "GET", "/api/v1/admin/metrics?days=7", adminToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("admin metrics = %d: %s", rec.Code, rec.Body.String())
	}
	body := decode(t, rec)
	if body["days"] != float64(7) {
		t.Fatalf("days = %v, want 7", body["days"])
	}
}

// insertEvent writes an analytics event with an explicit created_at so tests
// can shape retention windows (recordEvent always stamps now()).
func insertEvent(t *testing.T, userID uuid.UUID, eventType string, at time.Time, metadata string) {
	t.Helper()
	var meta any
	if metadata != "" {
		meta = metadata
	}
	_, err := dbPool.Exec(context.Background(),
		`INSERT INTO analytics_events (user_id, event_type, metadata, created_at)
		 VALUES ($1, $2, $3, $4)`, userID, eventType, meta, at)
	if err != nil {
		t.Fatalf("insertEvent(%s): %v", eventType, err)
	}
}

// insertTripCreated writes a trip_created event carrying its trip_id, the way
// plan_handler records it — second_trip_retention dedupes by the referenced
// trip's lineage, so the linkage matters.
func insertTripCreated(t *testing.T, userID, tripID uuid.UUID, at time.Time) {
	t.Helper()
	_, err := dbPool.Exec(context.Background(),
		`INSERT INTO analytics_events (user_id, event_type, trip_id, created_at)
		 VALUES ($1, 'trip_created', $2, $3)`, userID, tripID, at)
	if err != nil {
		t.Fatalf("insertTripCreated: %v", err)
	}
}

// createTripInLineage inserts a bare trips row in the given chat lineage —
// two calls with the same chatID model a version save (one lineage, two
// trip_created events).
func createTripInLineage(t *testing.T, owner uuid.UUID, chatID string) uuid.UUID {
	t.Helper()
	trip, err := store.New(dbPool).CreateTrip(context.Background(), store.CreateTripParams{
		UserID: owner, Title: "Lineage Trip", Status: "draft", ChatID: &chatID,
	})
	if err != nil {
		t.Fatalf("createTripInLineage(%s): %v", chatID, err)
	}
	return trip.ID
}

// TestAdminMetricsValues seeds a shaped event log and asserts the grouped
// counts, second-trip retention (≥2 distinct trip LINEAGES with first
// creations ≥7 days apart — version saves of one lineage never count), MAU,
// the Claude cost estimate, and the plan_cap_hits → agent_loop_cap_hits /
// returning_users → session_frequency_returning renames.
func TestAdminMetricsValues(t *testing.T) {
	resetDB(t)
	admin, adminToken := createTestUser(t, "admin2@example.com")
	makeAdmin(t, admin.ID)
	userA, _ := createTestUser(t, "retained@example.com")
	userB, _ := createTestUser(t, "notyet@example.com")
	userC, _ := createTestUser(t, "versioner@example.com")

	now := time.Now()
	insertEvent(t, userA.ID, "user_registered", now, "")
	insertEvent(t, userB.ID, "user_registered", now, "")
	insertEvent(t, userC.ID, "user_registered", now, "")

	// A: two DISTINCT lineages 8 days apart => counts toward
	// second_trip_retention.
	insertTripCreated(t, userA.ID, createTripInLineage(t, userA.ID, "chat-a1"), now.AddDate(0, 0, -8))
	insertTripCreated(t, userA.ID, createTripInLineage(t, userA.ID, "chat-a2"), now)
	// B: two distinct lineages only 2 days apart => session enthusiasm, not
	// retention.
	insertTripCreated(t, userB.ID, createTripInLineage(t, userB.ID, "chat-b1"), now.AddDate(0, 0, -2))
	insertTripCreated(t, userB.ID, createTripInLineage(t, userB.ID, "chat-b2"), now)
	// C: two trip_created events 8 days apart but on the SAME lineage (a
	// re-finalized chat, i.e. a version save) => must NOT count as retention.
	insertTripCreated(t, userC.ID, createTripInLineage(t, userC.ID, "chat-c1"), now.AddDate(0, 0, -8))
	insertTripCreated(t, userC.ID, createTripInLineage(t, userC.ID, "chat-c1"), now)

	// A is the sole active (MAU) user; one completed session that hit the
	// agent-loop cap and burned exactly 1M input + 1M output tokens
	// => est cost $3 + $15 = $18, all attributed to the one active user.
	insertEvent(t, userA.ID, "plan_session_started", now, "")
	insertEvent(t, userA.ID, "plan_session_completed", now,
		`{"input_tokens":1000000,"output_tokens":1000000,"cache_read_tokens":0,"cache_creation_tokens":0,"max_iterations_hit":true}`)

	rec := doJSON(t, "GET", "/api/v1/admin/metrics?days=30", adminToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("admin metrics = %d: %s", rec.Code, rec.Body.String())
	}
	body := decode(t, rec)

	// Grouped per-type counts (one GROUP BY query feeds all of these).
	for field, want := range map[string]float64{
		"signups":                     3,
		"trips_created":               6,
		"second_trip_retention":       1, // A only: B lacks the 7-day gap, C's gap is within one lineage
		"session_frequency_returning": 0, // A's sessions all on one day
		"active_users":                1,
		"plan_sessions":               1,
		"agent_loop_cap_hits":         1,
		"plan_input_tokens":           1000000,
		"plan_output_tokens":          1000000,
		"est_claude_cost_usd":         18,
		"est_cogs_per_active_user":    18,
	} {
		if body[field] != want {
			t.Errorf("%s = %v, want %v", field, body[field], want)
		}
	}

	if body["est_cost_model"] != "claude-sonnet-4-6" {
		t.Errorf("est_cost_model = %v, want claude-sonnet-4-6", body["est_cost_model"])
	}

	// The old, misleading field names must be gone.
	for _, gone := range []string{"plan_cap_hits", "returning_users"} {
		if _, ok := body[gone]; ok {
			t.Errorf("response still contains renamed field %q", gone)
		}
	}
}
