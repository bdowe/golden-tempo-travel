package main

import (
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

// Credential stuffing across many IPs must be stopped by the per-account
// lockout even though each request comes from a fresh IP (so the strict
// per-IP limiter never fires). After the threshold, even the CORRECT password
// is rejected with 429 — and identically for a non-existent account, preserving
// no-enumeration.
func TestLoginLockoutStopsCrossIPStuffing(t *testing.T) {
	resetDB(t)
	loginLockouts.resetAll()
	createTestUser(t, "locktarget@example.com") // password is "password123"

	// LOGIN_MAX_FAILURES defaults to 5. Each attempt uses a fresh unique IP.
	for i := 0; i < 5; i++ {
		rec := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
			"email": "locktarget@example.com", "password": "wrong-password",
		})
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("bad login %d = %d, want 401", i+1, rec.Code)
		}
	}
	// The correct password is now refused with 429 within the lock window.
	rec := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "locktarget@example.com", "password": "password123",
	})
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("locked login with correct password = %d, want 429", rec.Code)
	}
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("lockout 429 should carry Retry-After")
	}

	// A non-existent account locks the same way (enumeration-safe): the 429
	// reveals nothing about existence.
	loginLockouts.resetAll()
	for i := 0; i < 5; i++ {
		doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
			"email": "ghost@example.com", "password": "wrong-password",
		})
	}
	ghost := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "ghost@example.com", "password": "whatever",
	})
	if ghost.Code != http.StatusTooManyRequests {
		t.Fatalf("locked non-existent account = %d, want 429 (enumeration-safe)", ghost.Code)
	}
}

// A successful login before the threshold clears the failure streak.
func TestLoginLockoutResetsOnSuccess(t *testing.T) {
	resetDB(t)
	loginLockouts.resetAll()
	createTestUser(t, "resetstreak@example.com")

	for i := 0; i < 4; i++ { // one short of the default threshold (5)
		doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
			"email": "resetstreak@example.com", "password": "wrong-password",
		})
	}
	// Correct login succeeds and resets the streak.
	ok := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "resetstreak@example.com", "password": "password123",
	})
	if ok.Code != http.StatusOK {
		t.Fatalf("login before lockout = %d, want 200", ok.Code)
	}
	// Four more failures still don't lock (streak restarted at 0).
	for i := 0; i < 4; i++ {
		doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
			"email": "resetstreak@example.com", "password": "wrong-password",
		})
	}
	again := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "resetstreak@example.com", "password": "password123",
	})
	if again.Code != http.StatusOK {
		t.Fatalf("login after reset + <threshold failures = %d, want 200", again.Code)
	}
}

// Past the per-IP daily ceiling, registration is refused with a 429 that names
// the network cause (distinguishing it from the strict rate limiter).
func TestRegistrationCeilingPerIP(t *testing.T) {
	resetDB(t)
	registrationCounter.resetAll()
	t.Setenv("MAX_REGISTRATIONS_PER_IP_PER_DAY", "2")

	ip := nextTestIP() // one IP for all three; stays within the strict burst (3)
	codes := make([]int, 0, 3)
	for i := 0; i < 3; i++ {
		rec := doJSONFromIP(t, "POST", "/api/v1/auth/register", "", ip, map[string]any{
			"email": "reg" + nextTestIP() + "@example.com", "password": "hunter2hunter2",
		})
		codes = append(codes, rec.Code)
		if i == 2 {
			if rec.Code != http.StatusTooManyRequests {
				t.Fatalf("3rd register past ceiling = %d, want 429", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), "too many accounts created from this network") {
				t.Fatalf("ceiling 429 body = %q, want the network-ceiling message", rec.Body.String())
			}
		}
	}
	if codes[0] != http.StatusCreated || codes[1] != http.StatusCreated {
		t.Fatalf("first two registers = %v, want 201/201", codes[:2])
	}
}

// Two rapid password-reset requests for the same address deliver only one
// email (the per-address throttle skips the second send) while the user-facing
// response stays 202 both times, so the throttle can't be used to enumerate.
func TestPasswordResetEmailThrottled(t *testing.T) {
	resetDB(t)
	emailSendThrottle.resetAll()
	createTestUser(t, "bomb@example.com")

	var mu sync.Mutex
	sends := 0
	orig := emailSend
	emailSend = func(to, subject, body string) error {
		mu.Lock()
		sends++
		mu.Unlock()
		return nil
	}
	defer func() { emailSend = orig }()

	for i := 0; i < 2; i++ {
		rec := doJSON(t, "POST", "/api/v1/auth/request-password-reset", "", map[string]any{
			"email": "bomb@example.com",
		})
		if rec.Code != http.StatusAccepted {
			t.Fatalf("reset request %d = %d, want 202 (unchanged)", i+1, rec.Code)
		}
	}

	// Sends run in fire-and-forget goroutines; wait for the first, then give a
	// (wrongly) un-throttled second a chance to land. The throttle guarantees
	// at most one regardless of scheduling.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		mu.Lock()
		n := sends
		mu.Unlock()
		if n >= 1 {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	time.Sleep(150 * time.Millisecond)
	mu.Lock()
	n := sends
	mu.Unlock()
	if n != 1 {
		t.Fatalf("reset email sends = %d, want exactly 1 (second throttled)", n)
	}
}
