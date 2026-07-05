package main

import (
	"net/http"
	"testing"
)

func TestRegisterLoginFlow(t *testing.T) {
	resetDB(t)

	rec := doJSON(t, "POST", "/api/v1/auth/register", "", map[string]any{
		"email": "traveler@example.com", "password": "hunter2hunter2",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("register = %d: %s", rec.Code, rec.Body.String())
	}
	token, _ := decode(t, rec)["token"].(string)
	if token == "" {
		t.Fatal("register returned no token")
	}

	me := doJSON(t, "GET", "/api/v1/auth/me", token, nil)
	if me.Code != http.StatusOK {
		t.Fatalf("/auth/me with fresh token = %d", me.Code)
	}
	if decode(t, me)["email"] != "traveler@example.com" {
		t.Fatalf("/auth/me user payload wrong: %s", me.Body.String())
	}

	login := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "traveler@example.com", "password": "hunter2hunter2",
	})
	if login.Code != http.StatusOK {
		t.Fatalf("login = %d: %s", login.Code, login.Body.String())
	}
}

func TestRegisterDuplicateEmail(t *testing.T) {
	resetDB(t)
	createTestUser(t, "taken@example.com")

	rec := doJSON(t, "POST", "/api/v1/auth/register", "", map[string]any{
		"email": "taken@example.com", "password": "hunter2hunter2",
	})
	if rec.Code != http.StatusConflict {
		t.Fatalf("duplicate register = %d, want 409", rec.Code)
	}
}

func TestRegisterValidation(t *testing.T) {
	resetDB(t)

	if rec := doJSON(t, "POST", "/api/v1/auth/register", "", map[string]any{
		"email": "not-an-email", "password": "hunter2hunter2",
	}); rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("bad email = %d, want 422", rec.Code)
	}
	if rec := doJSON(t, "POST", "/api/v1/auth/register", "", map[string]any{
		"email": "ok@example.com", "password": "short",
	}); rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("short password = %d, want 422", rec.Code)
	}
}

// Wrong password and unknown email must be indistinguishable (no account
// enumeration).
func TestLoginFailuresIdentical(t *testing.T) {
	resetDB(t)
	createTestUser(t, "real@example.com")

	wrongPw := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "real@example.com", "password": "wrong-password",
	})
	noUser := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "ghost@example.com", "password": "wrong-password",
	})
	if wrongPw.Code != http.StatusUnauthorized || noUser.Code != http.StatusUnauthorized {
		t.Fatalf("login failures = %d/%d, want 401/401", wrongPw.Code, noUser.Code)
	}
	if wrongPw.Body.String() != noUser.Body.String() {
		t.Fatalf("failure bodies differ (enumeration risk): %q vs %q",
			wrongPw.Body.String(), noUser.Body.String())
	}
}

func TestAuthMeRejectsBadTokens(t *testing.T) {
	resetDB(t)

	if rec := doJSON(t, "GET", "/api/v1/auth/me", "", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("no token = %d, want 401", rec.Code)
	}
	if rec := doJSON(t, "GET", "/api/v1/auth/me", "totally-fake-token", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("garbage token = %d, want 401", rec.Code)
	}
}

func TestLogoutInvalidatesToken(t *testing.T) {
	resetDB(t)
	_, token := createTestUser(t, "bye@example.com")

	if rec := doJSON(t, "POST", "/api/v1/auth/logout", token, nil); rec.Code >= 300 {
		t.Fatalf("logout = %d", rec.Code)
	}
	if rec := doJSON(t, "GET", "/api/v1/auth/me", token, nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("token after logout = %d, want 401", rec.Code)
	}
}

// The strict limiter allows a burst of 3 per IP on auth routes; a 4th
// register from the same IP must 429. Every other test uses a unique IP.
func TestStrictRateLimiterOnRegister(t *testing.T) {
	resetDB(t)
	ip := nextTestIP()

	var last int
	for i := 0; i < 4; i++ {
		rec := doJSONFromIP(t, "POST", "/api/v1/auth/register", "", ip, map[string]any{
			"email": "spam" + nextTestIP() + "@example.com", "password": "hunter2hunter2",
		})
		last = rec.Code
	}
	if last != http.StatusTooManyRequests {
		t.Fatalf("4th register from one IP = %d, want 429", last)
	}
}
