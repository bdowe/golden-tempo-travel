package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// --- login lockout (fake clock, no DB) ---

func TestLockoutTrackerLocksAfterThreshold(t *testing.T) {
	window := 15 * time.Minute
	l := newLockoutTracker(func() int { return 5 }, func() time.Duration { return window })
	now := time.Unix(1_700_000_000, 0)

	for i := 0; i < 4; i++ {
		if l.recordFailure("victim@example.com", now) {
			t.Fatalf("failure %d should not lock yet", i+1)
		}
		if l.locked("victim@example.com", now) {
			t.Fatalf("account should not be locked after %d failures", i+1)
		}
	}
	// 5th failure trips the lock.
	if !l.recordFailure("victim@example.com", now) {
		t.Fatal("5th failure should lock the account")
	}
	if !l.locked("victim@example.com", now) {
		t.Fatal("account should be locked at the threshold")
	}
	// Still locked just before the window closes; unlocked after it.
	if !l.locked("victim@example.com", now.Add(window-time.Second)) {
		t.Fatal("account should remain locked within the window")
	}
	if l.locked("victim@example.com", now.Add(window+time.Second)) {
		t.Fatal("account should unlock after the window elapses")
	}
}

func TestLockoutTrackerResetClearsStreak(t *testing.T) {
	l := newLockoutTracker(func() int { return 5 }, func() time.Duration { return 15 * time.Minute })
	now := time.Unix(1_700_000_000, 0)

	for i := 0; i < 4; i++ {
		l.recordFailure("user@example.com", now)
	}
	// A success before lockout wipes the counter.
	l.reset("user@example.com")
	// It now takes a full fresh streak to lock again.
	for i := 0; i < 4; i++ {
		if l.recordFailure("user@example.com", now) {
			t.Fatalf("post-reset failure %d should not lock (streak restarted)", i+1)
		}
	}
	if l.locked("user@example.com", now) {
		t.Fatal("account should not be locked after reset + <threshold failures")
	}
}

func TestLockoutTrackerKeysAreIndependent(t *testing.T) {
	l := newLockoutTracker(func() int { return 3 }, func() time.Duration { return time.Minute })
	now := time.Unix(1_700_000_000, 0)
	for i := 0; i < 3; i++ {
		l.recordFailure("a@example.com", now)
	}
	if !l.locked("a@example.com", now) {
		t.Fatal("a should be locked")
	}
	if l.locked("b@example.com", now) {
		t.Fatal("b must not share a's lock")
	}
}

// --- anonymous /plan daily cap (fake clock, no DB) ---

func TestAnonPlanAllowedCapsAnonymousPerIP(t *testing.T) {
	anonPlanCounter.resetAll()
	t.Setenv("FREE_ANON_PLAN_PER_DAY", "3")
	now := time.Unix(1_700_000_000, 0).UTC()
	ip := "203.0.113.9"

	for i := 0; i < 3; i++ {
		if !anonPlanAllowed(false, ip, now) {
			t.Fatalf("anonymous request %d within cap should be allowed", i+1)
		}
	}
	if anonPlanAllowed(false, ip, now) {
		t.Fatal("anonymous request past the daily cap should be rejected")
	}
	// A different IP has its own budget.
	if !anonPlanAllowed(false, "198.51.100.7", now) {
		t.Fatal("a different IP must not share the exhausted budget")
	}
}

func TestAnonPlanAuthedExemptAndUncounted(t *testing.T) {
	anonPlanCounter.resetAll()
	t.Setenv("FREE_ANON_PLAN_PER_DAY", "2")
	now := time.Unix(1_700_000_000, 0).UTC()
	ip := "203.0.113.20"

	// Authenticated callers always pass, even far past the anon cap...
	for i := 0; i < 10; i++ {
		if !anonPlanAllowed(true, ip, now) {
			t.Fatal("authenticated caller must never be capped")
		}
	}
	// ...and must not consume any of the anonymous budget for that IP.
	if got := anonPlanCounter.count(ip, now); got != 0 {
		t.Fatalf("authed traffic consumed anon budget: count = %d, want 0", got)
	}
	if !anonPlanAllowed(false, ip, now) {
		t.Fatal("anon budget should be untouched by authed traffic")
	}
}

func TestAnonPlanCapResetsAtUTCMidnight(t *testing.T) {
	anonPlanCounter.resetAll()
	t.Setenv("FREE_ANON_PLAN_PER_DAY", "1")
	ip := "203.0.113.30"
	day1 := time.Date(2026, 1, 1, 23, 59, 0, 0, time.UTC)
	day2 := time.Date(2026, 1, 2, 0, 1, 0, 0, time.UTC)

	if !anonPlanAllowed(false, ip, day1) {
		t.Fatal("first request of the day should be allowed")
	}
	if anonPlanAllowed(false, ip, day1) {
		t.Fatal("second request same day should be capped")
	}
	if !anonPlanAllowed(false, ip, day2) {
		t.Fatal("counter should roll over at UTC midnight")
	}
}

// planHandler emits a friendly SSE error (not a 500) when the anon cap trips.
// No DB needed: with dbPool nil, userIDFromRequest resolves anonymous.
func TestPlanHandlerAnonCapEmitsFriendlySSE(t *testing.T) {
	anonPlanCounter.resetAll()
	t.Setenv("FREE_ANON_PLAN_PER_DAY", "1")
	// Ensure the first (allowed) request short-circuits at the API-key check
	// instead of attempting a real Anthropic call on a dev box that exports one.
	t.Setenv("ANTHROPIC_API_KEY", "")

	body := `{"messages":[{"role":"user","content":"hi"}]}`
	call := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/plan", strings.NewReader(body))
		req.Header.Set("X-Forwarded-For", "203.0.113.40")
		rec := httptest.NewRecorder()
		planHandler(rec, req)
		return rec
	}

	// First anonymous request passes the cap (whatever it does next).
	call()
	// Second trips the cap: 200 (SSE always) with the friendly cap message.
	rec := call()
	if rec.Code != http.StatusOK {
		t.Fatalf("capped /plan status = %d, want 200 (SSE error, never 500)", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "free planning limit") {
		t.Fatalf("capped /plan body = %q, want the friendly cap message", rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "\"type\":\"error\"") == false {
		t.Fatalf("capped /plan should emit an SSE error event, got %q", rec.Body.String())
	}
}

// --- email interval throttle ---

func TestIntervalThrottleEnforcesMinGap(t *testing.T) {
	tr := newIntervalThrottle()
	now := time.Unix(1_700_000_000, 0)
	gap := time.Minute

	if !tr.allow("reset:v@example.com", now, gap) {
		t.Fatal("first send should be allowed")
	}
	if tr.allow("reset:v@example.com", now.Add(30*time.Second), gap) {
		t.Fatal("second send within the min interval should be throttled")
	}
	if !tr.allow("reset:v@example.com", now.Add(61*time.Second), gap) {
		t.Fatal("send after the interval should be allowed")
	}
	// Distinct key (different purpose / address) is independent.
	if !tr.allow("verify:v@example.com", now.Add(30*time.Second), gap) {
		t.Fatal("a different throttle key must not be blocked")
	}
}

// --- concurrency limiter ---

func TestConcurrencyLimiterShedsWhenFullButExemptsHealth(t *testing.T) {
	cl := newConcurrencyLimiter(1)
	release := make(chan struct{})
	entered := make(chan struct{})
	h := cl.middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/health" {
			w.WriteHeader(http.StatusOK)
			return
		}
		entered <- struct{}{}
		<-release
		w.WriteHeader(http.StatusOK)
	}))

	// Occupy the single slot with a request parked inside the handler.
	go func() {
		h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/v1/plan", nil))
	}()
	<-entered

	// A second request finds the semaphore full and is shed immediately.
	shed := httptest.NewRecorder()
	h.ServeHTTP(shed, httptest.NewRequest(http.MethodGet, "/api/v1/anything", nil))
	if shed.Code != http.StatusServiceUnavailable {
		t.Fatalf("shed request status = %d, want 503", shed.Code)
	}
	if shed.Header().Get("Retry-After") == "" {
		t.Fatal("503 should carry Retry-After")
	}

	// /health is exempt and answers 200 even while saturated.
	hrec := httptest.NewRecorder()
	h.ServeHTTP(hrec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if hrec.Code != http.StatusOK {
		t.Fatalf("/health under saturation = %d, want 200", hrec.Code)
	}

	close(release)
}
