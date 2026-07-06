package main

import (
	"testing"

	"github.com/google/uuid"
)

// Cap values must be read from the environment at call time (per-test
// overridable) and fall back to the business-model placeholders on anything
// unset or invalid.
func TestFreeCapEnvValues(t *testing.T) {
	t.Setenv("FREE_PLAN_SESSIONS_PER_MONTH", "")
	t.Setenv("FREE_ACTIVE_TRIPS", "")
	if got := freePlanSessionsPerMonth(); got != defaultFreePlanSessionsPerMonth {
		t.Fatalf("unset plan cap = %d, want %d", got, defaultFreePlanSessionsPerMonth)
	}
	if got := freeActiveTrips(); got != defaultFreeActiveTrips {
		t.Fatalf("unset trips cap = %d, want %d", got, defaultFreeActiveTrips)
	}

	t.Setenv("FREE_PLAN_SESSIONS_PER_MONTH", "2")
	t.Setenv("FREE_ACTIVE_TRIPS", "1")
	if got := freePlanSessionsPerMonth(); got != 2 {
		t.Fatalf("plan cap = %d, want 2", got)
	}
	if got := freeActiveTrips(); got != 1 {
		t.Fatalf("trips cap = %d, want 1", got)
	}

	// Zero, negative, and garbage all fall back to the defaults.
	for _, bad := range []string{"0", "-5", "twenty"} {
		t.Setenv("FREE_PLAN_SESSIONS_PER_MONTH", bad)
		if got := freePlanSessionsPerMonth(); got != defaultFreePlanSessionsPerMonth {
			t.Fatalf("plan cap with %q = %d, want default %d", bad, got, defaultFreePlanSessionsPerMonth)
		}
	}
}

// Degraded mode (no database) must be a silent no-op: the signal helpers may
// never panic or block a request when dbPool is nil.
func TestFreeCapHelpersFailOpenWithoutDB(t *testing.T) {
	if dbPool != nil {
		t.Skip("requires degraded mode (run without TEST_DATABASE_URL)")
	}
	recordActiveTripsCapSignal(uuid.New(), uuid.New())
	uid := uuid.New()
	recordPlanSessionStart(&uid, true)
	recordPlanSessionStart(nil, false)
}
