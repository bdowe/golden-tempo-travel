package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"travel-route-planner/store"
)

// End-to-end tests for the Google SSO flow (specs/google-sso), driven against
// the fake token endpoint from fake_google_test.go. The Google consent screen
// itself never happens: tests capture the state+cookie from /auth/google and
// replay them straight to the callback, exactly like a browser would.

func startGoogle(t *testing.T) (state string, cookie *http.Cookie) {
	t.Helper()
	req := httptest.NewRequest("GET", "/api/v1/auth/google", nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	if rec.Code != http.StatusFound {
		t.Fatalf("/auth/google = %d: %s", rec.Code, rec.Body.String())
	}
	loc, err := url.Parse(rec.Header().Get("Location"))
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}
	state = loc.Query().Get("state")
	for _, c := range rec.Result().Cookies() {
		if c.Name == googleStateCookie {
			cookie = c
		}
	}
	if state == "" || cookie == nil {
		t.Fatalf("start flow missing state (%q) or cookie", state)
	}
	return state, cookie
}

func googleCallback(t *testing.T, rawQuery string, cookie *http.Cookie) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest("GET", "/api/v1/auth/google/callback?"+rawQuery, nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	if cookie != nil {
		req.AddCookie(cookie)
	}
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	return rec
}

// googleSignIn runs the whole redirect dance and returns the exchange
// response (login-shaped: {user, token}).
func googleSignIn(t *testing.T) map[string]any {
	t.Helper()
	state, cookie := startGoogle(t)
	rec := googleCallback(t, "code=fake-auth-code&state="+url.QueryEscape(state), cookie)
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("callback = %d: %s", rec.Code, rec.Body.String())
	}
	loc := rec.Header().Get("Location")
	code := loc[strings.LastIndex(loc, "/")+1:]
	if code == "error" || code == "" {
		t.Fatalf("callback redirected to %q, want /sso/<code>", loc)
	}
	ex := doJSON(t, "POST", "/api/v1/auth/google/exchange", "", map[string]any{"code": code})
	if ex.Code != http.StatusOK {
		t.Fatalf("exchange = %d: %s", ex.Code, ex.Body.String())
	}
	return decode(t, ex)
}

func countRows(t *testing.T, table string) int {
	t.Helper()
	var n int
	if err := dbPool.QueryRow(context.Background(), "SELECT count(*) FROM "+table).Scan(&n); err != nil {
		t.Fatalf("count %s: %v", table, err)
	}
	return n
}

func TestGoogleAvailability(t *testing.T) {
	requireDB(t)
	rec := doJSON(t, "GET", "/api/v1/auth/google/availability", "", nil)
	if rec.Code != http.StatusOK || decode(t, rec)["available"] != false {
		t.Fatalf("unconfigured availability = %d %s, want available:false", rec.Code, rec.Body.String())
	}

	setupFakeGoogle(t, testGoogleClaims("any@example.com", ""))
	rec = doJSON(t, "GET", "/api/v1/auth/google/availability", "", nil)
	if rec.Code != http.StatusOK || decode(t, rec)["available"] != true {
		t.Fatalf("configured availability = %d %s, want available:true", rec.Code, rec.Body.String())
	}
}

func TestGoogleStartUnconfigured(t *testing.T) {
	requireDB(t)
	req := httptest.NewRequest("GET", "/api/v1/auth/google", nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("/auth/google unconfigured = %d, want 503", rec.Code)
	}
}

func TestGoogleStartRedirect(t *testing.T) {
	requireDB(t)
	setupFakeGoogle(t, testGoogleClaims("any@example.com", ""))

	req := httptest.NewRequest("GET", "/api/v1/auth/google", nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	if rec.Code != http.StatusFound {
		t.Fatalf("/auth/google = %d", rec.Code)
	}
	loc, err := url.Parse(rec.Header().Get("Location"))
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}
	if loc.Host != "accounts.google.com" {
		t.Fatalf("redirect host = %q", loc.Host)
	}
	q := loc.Query()
	if q.Get("client_id") != testGoogleClientID ||
		q.Get("response_type") != "code" ||
		q.Get("code_challenge_method") != "S256" ||
		q.Get("code_challenge") == "" ||
		q.Get("state") == "" {
		t.Fatalf("redirect query incomplete: %s", loc.RawQuery)
	}
	if q.Get("redirect_uri") != "http://localhost:3000/api/v1/auth/google/callback" {
		t.Fatalf("redirect_uri = %q", q.Get("redirect_uri"))
	}
	var cookie *http.Cookie
	for _, c := range rec.Result().Cookies() {
		if c.Name == googleStateCookie {
			cookie = c
		}
	}
	if cookie == nil || !cookie.HttpOnly {
		t.Fatalf("state cookie missing or not HttpOnly: %+v", cookie)
	}
	// state must be in the cookie alongside the PKCE verifier
	if got, _, _ := strings.Cut(cookie.Value, "."); got != q.Get("state") {
		t.Fatalf("cookie state %q != redirect state %q", got, q.Get("state"))
	}
}

func TestGoogleCallbackStateMismatch(t *testing.T) {
	resetDB(t)
	setupFakeGoogle(t, testGoogleClaims("victim@example.com", ""))

	_, cookie := startGoogle(t)
	rec := googleCallback(t, "code=fake-auth-code&state=tampered", cookie)
	if rec.Code != http.StatusSeeOther || !strings.HasSuffix(rec.Header().Get("Location"), "/sso/error") {
		t.Fatalf("tampered state → %d %q, want 303 /sso/error", rec.Code, rec.Header().Get("Location"))
	}
	if countRows(t, "users") != 0 {
		t.Fatal("tampered callback must not create a user")
	}
}

func TestGoogleCallbackDeclined(t *testing.T) {
	resetDB(t)
	setupFakeGoogle(t, testGoogleClaims("nope@example.com", ""))

	state, cookie := startGoogle(t)
	rec := googleCallback(t, "error=access_denied&state="+url.QueryEscape(state), cookie)
	if rec.Code != http.StatusSeeOther || !strings.HasSuffix(rec.Header().Get("Location"), "/sso/error") {
		t.Fatalf("declined consent → %d %q, want 303 /sso/error", rec.Code, rec.Header().Get("Location"))
	}
}

func TestGoogleSignInHappyPath(t *testing.T) {
	resetDB(t)
	setupFakeGoogle(t, testGoogleClaims("newbie@example.com", "New Traveler"))

	resp := googleSignIn(t)
	token, _ := resp["token"].(string)
	user, _ := resp["user"].(map[string]any)
	if token == "" || user == nil {
		t.Fatalf("exchange response malformed: %v", resp)
	}
	if user["email"] != "newbie@example.com" || user["display_name"] != "New Traveler" {
		t.Fatalf("user payload wrong: %v", user)
	}
	if user["needs_onboarding"] != true {
		t.Fatal("fresh Google user should owe the onboarding quiz")
	}

	me := doJSON(t, "GET", "/api/v1/auth/me", token, nil)
	if me.Code != http.StatusOK {
		t.Fatalf("/auth/me with SSO session = %d", me.Code)
	}

	dbUser, err := store.New(dbPool).GetUserByEmail(context.Background(), "newbie@example.com")
	if err != nil {
		t.Fatalf("user not in DB: %v", err)
	}
	if !dbUser.EmailVerifiedAt.Valid {
		t.Fatal("Google-created user should be email-verified")
	}
	if dbUser.PasswordHash != nil {
		t.Fatal("Google-created user should have no password hash")
	}
	if countRows(t, "auth_identities") != 1 {
		t.Fatal("expected one auth_identities row")
	}
}

func TestGoogleSignInSameSubTwice(t *testing.T) {
	resetDB(t)
	setupFakeGoogle(t, testGoogleClaims("repeat@example.com", ""))

	first := googleSignIn(t)
	second := googleSignIn(t)
	u1, _ := first["user"].(map[string]any)
	u2, _ := second["user"].(map[string]any)
	if u1["id"] != u2["id"] {
		t.Fatalf("same Google sub produced two users: %v / %v", u1["id"], u2["id"])
	}
	if countRows(t, "users") != 1 || countRows(t, "auth_identities") != 1 {
		t.Fatal("repeat sign-in must not duplicate user or identity")
	}
}

func TestGoogleAutoLinkExistingEmail(t *testing.T) {
	resetDB(t)
	existing, _ := createTestUser(t, "linked@example.com")
	setupFakeGoogle(t, testGoogleClaims("linked@example.com", ""))

	resp := googleSignIn(t)
	user, _ := resp["user"].(map[string]any)
	if user["id"] != existing.ID.String() {
		t.Fatalf("verified Google email should link to existing user %s, got %v", existing.ID, user["id"])
	}
	if countRows(t, "users") != 1 {
		t.Fatal("auto-link must not create a second account")
	}

	// The original password still works after linking.
	login := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "linked@example.com", "password": "password123",
	})
	if login.Code != http.StatusOK {
		t.Fatalf("password login after link = %d", login.Code)
	}
}

func TestGoogleUnverifiedEmailRefused(t *testing.T) {
	resetDB(t)
	createTestUser(t, "target@example.com")
	claims := testGoogleClaims("target@example.com", "")
	claims.EmailVerified = false
	setupFakeGoogle(t, claims)

	state, cookie := startGoogle(t)
	rec := googleCallback(t, "code=fake-auth-code&state="+url.QueryEscape(state), cookie)
	if rec.Code != http.StatusSeeOther || !strings.HasSuffix(rec.Header().Get("Location"), "/sso/error") {
		t.Fatalf("unverified email → %d %q, want 303 /sso/error", rec.Code, rec.Header().Get("Location"))
	}
	if countRows(t, "auth_identities") != 0 {
		t.Fatal("unverified Google email must never link (takeover guard)")
	}
}

func TestGoogleExchangeCodeSingleUse(t *testing.T) {
	resetDB(t)
	setupFakeGoogle(t, testGoogleClaims("onceonly@example.com", ""))

	state, cookie := startGoogle(t)
	rec := googleCallback(t, "code=fake-auth-code&state="+url.QueryEscape(state), cookie)
	loc := rec.Header().Get("Location")
	code := loc[strings.LastIndex(loc, "/")+1:]

	if ex := doJSON(t, "POST", "/api/v1/auth/google/exchange", "", map[string]any{"code": code}); ex.Code != http.StatusOK {
		t.Fatalf("first exchange = %d", ex.Code)
	}
	if ex := doJSON(t, "POST", "/api/v1/auth/google/exchange", "", map[string]any{"code": code}); ex.Code != http.StatusNotFound {
		t.Fatalf("replayed exchange = %d, want 404", ex.Code)
	}
	if ex := doJSON(t, "POST", "/api/v1/auth/google/exchange", "", map[string]any{"code": "bogus"}); ex.Code != http.StatusNotFound {
		t.Fatalf("bogus code exchange = %d, want 404", ex.Code)
	}
}

// SSO-only accounts (nil password hash) get sane credential-route behavior.
func TestSsoOnlyAccountPolicies(t *testing.T) {
	resetDB(t)
	setupFakeGoogle(t, testGoogleClaims("ssoonly@example.com", ""))
	resp := googleSignIn(t)
	token, _ := resp["token"].(string)

	// Password login: generic 401, indistinguishable from a wrong password.
	login := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "ssoonly@example.com", "password": "whatever123",
	})
	if login.Code != http.StatusUnauthorized {
		t.Fatalf("password login on SSO-only account = %d, want 401", login.Code)
	}

	// Change-password: 422 pointing at the reset flow.
	change := doJSON(t, "POST", "/api/v1/auth/change-password", token, map[string]any{
		"current_password": "", "new_password": "newpassword123",
	})
	if change.Code != http.StatusUnprocessableEntity {
		t.Fatalf("change-password on SSO-only account = %d, want 422", change.Code)
	}

	// Delete: allowed on the session alone (no password to re-verify).
	del := doJSON(t, "DELETE", "/api/v1/auth/account", token, map[string]any{"password": ""})
	if del.Code != http.StatusNoContent {
		t.Fatalf("delete SSO-only account = %d: %s", del.Code, del.Body.String())
	}
	if countRows(t, "users") != 0 {
		t.Fatal("account should be gone")
	}
}
