package main

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

// Integration coverage for specs/free-cap-instrumentation: env-lowered caps
// drive a user across each line, and we assert (a) exactly ONE
// free_cap_would_hit per crossing — the only-on-crossing rule's off-by-ones,
// (b) the dashboard rollup, and (c) that every capped request still SUCCEEDS
// (measurement only, nothing enforced).

// waitForEventCount polls until the user has exactly want events of the given
// type. plan_session_started is recorded by a goroutine that writes any
// crossing signal FIRST, so once the started count is visible the would-hit
// state for that session is settled too.
func waitForEventCount(t *testing.T, userID uuid.UUID, eventType string, want int) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		n := countUserEvents(t, userID, eventType)
		if n == want {
			return
		}
		if n > want {
			t.Fatalf("%s count = %d, exceeded expected %d", eventType, n, want)
		}
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %d %s events (have %d)", want, eventType, n)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func countUserEvents(t *testing.T, userID uuid.UUID, eventType string) int {
	t.Helper()
	var n int
	err := dbPool.QueryRow(context.Background(),
		`SELECT count(*) FROM analytics_events WHERE user_id = $1 AND event_type = $2`,
		userID, eventType).Scan(&n)
	if err != nil {
		t.Fatalf("countUserEvents(%s): %v", eventType, err)
	}
	return n
}

// freeCapWouldHits returns how many free_cap_would_hit rows the user has for
// a cap kind, plus the recorded metadata count of the newest one (0 if none).
func freeCapWouldHits(t *testing.T, userID uuid.UUID, capKind string) (hits, lastCount int) {
	t.Helper()
	err := dbPool.QueryRow(context.Background(),
		`SELECT count(*), COALESCE(max((metadata->>'count')::int), 0)
		 FROM analytics_events
		 WHERE user_id = $1 AND event_type = 'free_cap_would_hit'
		   AND metadata->>'cap_kind' = $2`,
		userID, capKind).Scan(&hits, &lastCount)
	if err != nil {
		t.Fatalf("freeCapWouldHits(%s): %v", capKind, err)
	}
	return hits, lastCount
}

// plan_runs: with the cap lowered to 2, sessions 1 and 2 are free, session 3
// is the crossing (prior count == cap) and emits exactly one signal, session
// 4 (prior > cap) emits nothing more. Every session must succeed.
func TestFreeCapPlanRunsCrossingSignal(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t, textTurn("Where would you like to go?"))
	t.Setenv("FREE_PLAN_SESSIONS_PER_MONTH", "2")

	user, token := createTestUser(t, "capped@example.com")

	for i := 1; i <= 4; i++ {
		rec := doJSON(t, "POST", "/api/v1/plan", token, PlanRequest{
			ChatID:   fmt.Sprintf("chat-%d", i),
			Messages: []PlanChatMessage{{Role: "user", Content: "plan me a weekend trip"}},
		})
		// Fail-open guarantee: the request SUCCEEDS whether or not the cap
		// would have been hit.
		if rec.Code != http.StatusOK {
			t.Fatalf("session %d: /plan = %d, want 200 (never rejected)", i, rec.Code)
		}
		out := rec.Body.String()
		if !strings.Contains(out, `"type":"text_delta"`) || strings.Contains(out, `"type":"error"`) {
			t.Fatalf("session %d: stream = %q, want a normal text stream with no error event", i, out)
		}

		waitForEventCount(t, user.ID, "plan_session_started", i)

		wantHits := 0
		if i >= 3 {
			wantHits = 1 // crossing at session cap+1 = 3, and only there
		}
		hits, lastCount := freeCapWouldHits(t, user.ID, "plan_runs")
		if hits != wantHits {
			t.Fatalf("after session %d: plan_runs would-hits = %d, want %d", i, hits, wantHits)
		}
		if i >= 3 && lastCount != 3 {
			t.Fatalf("would-hit metadata count = %d, want 3 (cap+1)", lastCount)
		}
	}

	// Dashboard rollup: one crossing, one distinct user affected.
	admin, adminToken := createTestUser(t, "metrics-admin@example.com")
	makeAdmin(t, admin.ID)
	rec := doJSON(t, "GET", "/api/v1/admin/metrics?days=30", adminToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("admin metrics = %d: %s", rec.Code, rec.Body.String())
	}
	body := decode(t, rec)
	wouldHits, _ := body["free_cap_would_hits"].(map[string]any)
	usersAffected, _ := body["free_cap_users_affected"].(map[string]any)
	if wouldHits["plan_runs"] != float64(1) {
		t.Fatalf("free_cap_would_hits.plan_runs = %v, want 1", wouldHits["plan_runs"])
	}
	if usersAffected["plan_runs"] != float64(1) {
		t.Fatalf("free_cap_users_affected.plan_runs = %v, want 1", usersAffected["plan_runs"])
	}
}

// active_trips: with the cap lowered to 1, the copier's first duplicate is
// within the cap, the second is the crossing (post-creation lineages ==
// cap+1) and emits exactly once, the third emits nothing. Every duplicate
// must succeed.
func TestFreeCapActiveTripsCrossingSignal(t *testing.T) {
	resetDB(t)
	t.Setenv("FREE_ACTIVE_TRIPS", "1")

	owner, ownerToken := createTestUser(t, "owner@example.com")
	copier, copierToken := createTestUser(t, "copier@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "")

	for i := 1; i <= 3; i++ {
		rec := doJSON(t, "POST", "/api/v1/shared/"+shareToken+"/duplicate", copierToken, nil)
		if rec.Code != http.StatusCreated {
			t.Fatalf("duplicate %d = %d, want 201 (never rejected): %s", i, rec.Code, rec.Body.String())
		}

		// The duplicate-path signal is synchronous, so this is settled here.
		wantHits := 0
		if i >= 2 {
			wantHits = 1 // crossing at trip cap+1 = 2, and only there
		}
		hits, lastCount := freeCapWouldHits(t, copier.ID, "active_trips")
		if hits != wantHits {
			t.Fatalf("after duplicate %d: active_trips would-hits = %d, want %d", i, hits, wantHits)
		}
		if i >= 2 && lastCount != 2 {
			t.Fatalf("would-hit metadata count = %d, want 2 (cap+1)", lastCount)
		}
	}

	// The crossing event carries the trip that crossed the line.
	var withTrip int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*) FROM analytics_events
		 WHERE user_id = $1 AND event_type = 'free_cap_would_hit' AND trip_id IS NOT NULL`,
		copier.ID).Scan(&withTrip); err != nil {
		t.Fatalf("trip_id check: %v", err)
	}
	if withTrip != 1 {
		t.Fatalf("would-hit rows with trip_id = %d, want 1", withTrip)
	}

	// The owner never crossed anything.
	if hits, _ := freeCapWouldHits(t, owner.ID, "active_trips"); hits != 0 {
		t.Fatalf("owner would-hits = %d, want 0", hits)
	}
}

// free_cap_would_hit is a SERVER-recorded event: the client event endpoint
// must keep rejecting it (spoofable demand signal otherwise).
func TestFreeCapEventNotClientRecordable(t *testing.T) {
	resetDB(t)
	user, token := createTestUser(t, "spoofer@example.com")

	rec := doJSON(t, "POST", "/api/v1/events", token, map[string]any{
		"event_type": "free_cap_would_hit",
		"metadata":   map[string]any{"cap_kind": "plan_runs", "count": 999},
	})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("client-recorded free_cap_would_hit = %d, want 400", rec.Code)
	}
	if n := countUserEvents(t, user.ID, "free_cap_would_hit"); n != 0 {
		t.Fatalf("spoofed events recorded = %d, want 0", n)
	}
}

// Version saves must never re-emit the active_trips crossing signal
// (specs/free-cap-instrumentation: "Saving a new version of an existing trip
// does not increase the count and can never emit"). With the cap at 1 and one
// pre-existing lineage, the FIRST finalize of a new chat is the crossing
// (2 lineages == cap+1) and emits once; re-finalizing the SAME chat creates
// new versions, leaves the lineage count parked at exactly cap+1, and — the
// regression this guards — must not emit again.
func TestFreeCapActiveTripsVersionSaveNeverReemits(t *testing.T) {
	resetDB(t)
	// Turn 0: finalize a trip (drives plan_handler's persistTrip branch);
	// turn 1 (after the tool_result round-trips): a plain end_turn answer.
	newFakeAnthropic(t,
		toolTurn("create_itinerary", `{"title":"Athens Weekend","locations":[{"name":"Acropolis","latitude":37.97,"longitude":23.72,"day":1}]}`),
		textTurn("Your itinerary is saved."))
	t.Setenv("FREE_ACTIVE_TRIPS", "1") // envInt treats 0 as invalid, so park the user at cap via a seed trip

	user, token := createTestUser(t, "re-finalizer@example.com")
	createTestTrip(t, user.ID, 1) // lineage #1: the user sits exactly at the cap

	for i := 1; i <= 3; i++ {
		rec := doJSON(t, "POST", "/api/v1/plan", token, PlanRequest{
			ChatID:   "chat-refinalize", // SAME chat: saves 2 and 3 are versions
			Messages: []PlanChatMessage{{Role: "user", Content: "plan athens"}},
		})
		if rec.Code != http.StatusOK {
			t.Fatalf("session %d: /plan = %d, want 200", i, rec.Code)
		}
		if out := rec.Body.String(); !strings.Contains(out, `"trip_id"`) {
			t.Fatalf("session %d: stream carried no persisted trip_id: %q", i, out)
		}
		// trip_created still fires per version (the event stream is not what
		// changed); poll it so the version row is committed and the signal
		// goroutine for this save has been decided.
		waitForEventCount(t, user.ID, "trip_created", i)
	}

	// All three finalizes landed in one lineage (plus the seed).
	var lineages int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(DISTINCT COALESCE(chat_id, id::text)) FROM trips WHERE user_id = $1`,
		user.ID).Scan(&lineages); err != nil {
		t.Fatalf("lineage count: %v", err)
	}
	if lineages != 2 {
		t.Fatalf("lineages = %d, want 2 (seed + one chat lineage; same-chat saves must be versions)", lineages)
	}

	// The crossing emitted exactly once — on the first save. The signal for a
	// version save is gated out synchronously (never spawned), so after the
	// settle window any extra emission would be visible.
	time.Sleep(300 * time.Millisecond)
	hits, lastCount := freeCapWouldHits(t, user.ID, "active_trips")
	if hits != 1 {
		t.Fatalf("active_trips would-hits = %d, want exactly 1 (version saves must not re-emit)", hits)
	}
	if lastCount != 2 {
		t.Fatalf("would-hit metadata count = %d, want 2 (cap+1)", lastCount)
	}
}
