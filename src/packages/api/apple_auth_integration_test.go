package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"travel-route-planner/store"
)

// End-to-end tests for Sign in with Apple (specs/apple-sso), driven against
// the fake token endpoint from fake_apple_test.go. Apple's consent sheet never
// happens: tests capture state+cookie from /auth/apple and replay them to the
// callback as the form_post POST a browser would deliver.

func startApple(t *testing.T) (state string, cookie *http.Cookie) {
	t.Helper()
	req := httptest.NewRequest("GET", "/api/v1/auth/apple", nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	if rec.Code != http.StatusFound {
		t.Fatalf("/auth/apple = %d: %s", rec.Code, rec.Body.String())
	}
	loc, err := url.Parse(rec.Header().Get("Location"))
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}
	state = loc.Query().Get("state")
	for _, c := range rec.Result().Cookies() {
		if c.Name == appleStateCookie {
			cookie = c
		}
	}
	if state == "" || cookie == nil {
		t.Fatalf("start flow missing state (%q) or cookie", state)
	}
	return state, cookie
}

// appleCallback delivers Apple's cross-site form_post to the callback.
func appleCallback(t *testing.T, form url.Values, cookie *http.Cookie) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest("POST", "/api/v1/auth/apple/callback", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("X-Forwarded-For", nextTestIP())
	if cookie != nil {
		req.AddCookie(cookie)
	}
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	return rec
}

// appleSignIn runs the whole dance and returns the exchange response.
// userField mimics the once-only `user` form field ("" to omit).
func appleSignIn(t *testing.T, userField string) map[string]any {
	t.Helper()
	state, cookie := startApple(t)
	form := url.Values{"code": {"fake-auth-code"}, "state": {state}}
	if userField != "" {
		form.Set("user", userField)
	}
	rec := appleCallback(t, form, cookie)
	if rec.Code != http.StatusSeeOther {
		t.Fatalf("callback = %d: %s", rec.Code, rec.Body.String())
	}
	loc := rec.Header().Get("Location")
	code := loc[strings.LastIndex(loc, "/")+1:]
	if code == "error" || code == "" {
		t.Fatalf("callback redirected to %q, want /sso/<code>", loc)
	}
	ex := doJSON(t, "POST", "/api/v1/auth/sso/exchange", "", map[string]any{"code": code})
	if ex.Code != http.StatusOK {
		t.Fatalf("exchange = %d: %s", ex.Code, ex.Body.String())
	}
	return decode(t, ex)
}

func TestAppleAvailability(t *testing.T) {
	requireDB(t)
	rec := doJSON(t, "GET", "/api/v1/auth/apple/availability", "", nil)
	if rec.Code != http.StatusOK || decode(t, rec)["available"] != false {
		t.Fatalf("unconfigured availability = %d %s, want available:false", rec.Code, rec.Body.String())
	}

	setupFakeApple(t, testAppleClaims("any@example.com"))
	rec = doJSON(t, "GET", "/api/v1/auth/apple/availability", "", nil)
	if rec.Code != http.StatusOK || decode(t, rec)["available"] != true {
		t.Fatalf("configured availability = %d %s, want available:true", rec.Code, rec.Body.String())
	}
}

func TestAppleStartUnconfigured(t *testing.T) {
	requireDB(t)
	req := httptest.NewRequest("GET", "/api/v1/auth/apple", nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("/auth/apple unconfigured = %d, want 503", rec.Code)
	}
}

func TestAppleStartRedirect(t *testing.T) {
	requireDB(t)
	setupFakeApple(t, testAppleClaims("any@example.com"))

	req := httptest.NewRequest("GET", "/api/v1/auth/apple", nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	if rec.Code != http.StatusFound {
		t.Fatalf("/auth/apple = %d", rec.Code)
	}
	loc, err := url.Parse(rec.Header().Get("Location"))
	if err != nil {
		t.Fatalf("parse redirect: %v", err)
	}
	if loc.Host != "appleid.apple.com" {
		t.Fatalf("redirect host = %q", loc.Host)
	}
	q := loc.Query()
	if q.Get("client_id") != testAppleClientID ||
		q.Get("response_type") != "code" ||
		q.Get("response_mode") != "form_post" ||
		q.Get("scope") != "name email" ||
		q.Get("state") == "" {
		t.Fatalf("redirect query incomplete: %s", loc.RawQuery)
	}
	if q.Get("code_challenge") != "" {
		t.Fatal("Apple flow must not send PKCE code_challenge")
	}
	if q.Get("redirect_uri") != "http://localhost:3000/api/v1/auth/apple/callback" {
		t.Fatalf("redirect_uri = %q", q.Get("redirect_uri"))
	}
	var cookie *http.Cookie
	for _, c := range rec.Result().Cookies() {
		if c.Name == appleStateCookie {
			cookie = c
		}
	}
	if cookie == nil || !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteNoneMode {
		t.Fatalf("state cookie must be HttpOnly+Secure+SameSite=None: %+v", cookie)
	}
	// Cookie carries the bare state (no PKCE verifier appended).
	if cookie.Value != q.Get("state") {
		t.Fatalf("cookie value %q != redirect state %q", cookie.Value, q.Get("state"))
	}
}

func TestAppleCallbackStateMismatch(t *testing.T) {
	resetDB(t)
	setupFakeApple(t, testAppleClaims("victim@example.com"))

	_, cookie := startApple(t)
	rec := appleCallback(t, url.Values{"code": {"fake-auth-code"}, "state": {"tampered"}}, cookie)
	if rec.Code != http.StatusSeeOther || !strings.HasSuffix(rec.Header().Get("Location"), "/sso/error") {
		t.Fatalf("tampered state → %d %q, want 303 /sso/error", rec.Code, rec.Header().Get("Location"))
	}
	if countRows(t, "users") != 0 {
		t.Fatal("tampered callback must not create a user")
	}
}

func TestAppleCallbackDeclined(t *testing.T) {
	resetDB(t)
	setupFakeApple(t, testAppleClaims("nope@example.com"))

	state, cookie := startApple(t)
	rec := appleCallback(t, url.Values{"error": {"user_cancelled"}, "state": {state}}, cookie)
	if rec.Code != http.StatusSeeOther || !strings.HasSuffix(rec.Header().Get("Location"), "/sso/error") {
		t.Fatalf("declined → %d %q, want 303 /sso/error", rec.Code, rec.Header().Get("Location"))
	}
}

func TestAppleSignInHappyPathWithNameCapture(t *testing.T) {
	resetDB(t)
	setupFakeApple(t, testAppleClaims("newbie@apple-example.com"))

	resp := appleSignIn(t, `{"name":{"firstName":"Ada","lastName":"Lovelace"},"email":"newbie@apple-example.com"}`)
	token, _ := resp["token"].(string)
	user, _ := resp["user"].(map[string]any)
	if token == "" || user == nil {
		t.Fatalf("exchange response malformed: %v", resp)
	}
	if user["email"] != "newbie@apple-example.com" || user["display_name"] != "Ada Lovelace" {
		t.Fatalf("user payload wrong (name should come from the user form field): %v", user)
	}
	if user["needs_onboarding"] != true {
		t.Fatal("fresh Apple user should owe the onboarding quiz")
	}

	me := doJSON(t, "GET", "/api/v1/auth/me", token, nil)
	if me.Code != http.StatusOK {
		t.Fatalf("/auth/me with SSO session = %d", me.Code)
	}

	dbUser, err := store.New(dbPool).GetUserByEmail(context.Background(), "newbie@apple-example.com")
	if err != nil {
		t.Fatalf("user not in DB: %v", err)
	}
	if !dbUser.EmailVerifiedAt.Valid || dbUser.PasswordHash != nil {
		t.Fatal("Apple-created user should be email-verified with no password hash")
	}
	if countRows(t, "auth_identities") != 1 {
		t.Fatal("expected one auth_identities row")
	}
}

// The `user` field arrives only on the first authorization; repeats must
// still resolve to the same account without it.
func TestAppleRepeatSignInWithoutUserField(t *testing.T) {
	resetDB(t)
	setupFakeApple(t, testAppleClaims("repeat@apple-example.com"))

	first := appleSignIn(t, `{"name":{"firstName":"Only","lastName":"Once"}}`)
	second := appleSignIn(t, "")
	u1, _ := first["user"].(map[string]any)
	u2, _ := second["user"].(map[string]any)
	if u1["id"] != u2["id"] {
		t.Fatalf("same Apple sub produced two users: %v / %v", u1["id"], u2["id"])
	}
	if u2["display_name"] != "Only Once" {
		t.Fatalf("display name should persist from first auth, got %v", u2["display_name"])
	}
	if countRows(t, "users") != 1 || countRows(t, "auth_identities") != 1 {
		t.Fatal("repeat sign-in must not duplicate user or identity")
	}
}

func TestAppleAutoLinkExistingEmail(t *testing.T) {
	resetDB(t)
	existing, _ := createTestUser(t, "linked@apple-example.com")
	setupFakeApple(t, testAppleClaims("linked@apple-example.com"))

	resp := appleSignIn(t, "")
	user, _ := resp["user"].(map[string]any)
	if user["id"] != existing.ID.String() {
		t.Fatalf("verified Apple email should link to existing user %s, got %v", existing.ID, user["id"])
	}
	if countRows(t, "users") != 1 {
		t.Fatal("auto-link must not create a second account")
	}

	login := doJSON(t, "POST", "/api/v1/auth/login", "", map[string]any{
		"email": "linked@apple-example.com", "password": "password123",
	})
	if login.Code != http.StatusOK {
		t.Fatalf("password login after link = %d", login.Code)
	}
}

func TestAppleUnverifiedOrMissingEmailRefused(t *testing.T) {
	resetDB(t)
	createTestUser(t, "target@apple-example.com")

	cases := map[string]map[string]any{
		"bool false":    testAppleClaims("target@apple-example.com"),
		"string false":  testAppleClaims("target@apple-example.com"),
		"missing email": testAppleClaims("target@apple-example.com"),
	}
	cases["bool false"]["email_verified"] = false
	cases["string false"]["email_verified"] = "false"
	delete(cases["missing email"], "email")

	for name, claims := range cases {
		setupFakeApple(t, claims)
		state, cookie := startApple(t)
		rec := appleCallback(t, url.Values{"code": {"fake-auth-code"}, "state": {state}}, cookie)
		if rec.Code != http.StatusSeeOther || !strings.HasSuffix(rec.Header().Get("Location"), "/sso/error") {
			t.Fatalf("%s → %d %q, want 303 /sso/error", name, rec.Code, rec.Header().Get("Location"))
		}
	}
	if countRows(t, "auth_identities") != 0 {
		t.Fatal("unverified/missing Apple email must never link (takeover guard)")
	}
}

// Apple sends booleans as strings sometimes; "true" must work end to end.
func TestAppleEmailVerifiedAsString(t *testing.T) {
	resetDB(t)
	claims := testAppleClaims("stringy@apple-example.com")
	claims["email_verified"] = "true"
	setupFakeApple(t, claims)

	resp := appleSignIn(t, "")
	if user, _ := resp["user"].(map[string]any); user["email"] != "stringy@apple-example.com" {
		t.Fatalf("string email_verified should sign in: %v", resp)
	}
}

// Hide-My-Email relay addresses are verified real addresses; they create a
// fresh account (they'll never match an existing email).
func TestApplePrivateRelayEmail(t *testing.T) {
	resetDB(t)
	claims := testAppleClaims("abc123xyz@privaterelay.appleid.com")
	claims["is_private_email"] = "true"
	setupFakeApple(t, claims)

	resp := appleSignIn(t, "")
	user, _ := resp["user"].(map[string]any)
	if user["email"] != "abc123xyz@privaterelay.appleid.com" {
		t.Fatalf("relay email should create an account: %v", resp)
	}
	if countRows(t, "users") != 1 {
		t.Fatal("expected exactly one account for the relay address")
	}
}

func TestAppleExchangeCodeSingleUseAndAlias(t *testing.T) {
	resetDB(t)
	setupFakeApple(t, testAppleClaims("onceonly@apple-example.com"))

	state, cookie := startApple(t)
	rec := appleCallback(t, url.Values{"code": {"fake-auth-code"}, "state": {state}}, cookie)
	loc := rec.Header().Get("Location")
	code := loc[strings.LastIndex(loc, "/")+1:]

	if ex := doJSON(t, "POST", "/api/v1/auth/sso/exchange", "", map[string]any{"code": code}); ex.Code != http.StatusOK {
		t.Fatalf("first exchange = %d", ex.Code)
	}
	if ex := doJSON(t, "POST", "/api/v1/auth/sso/exchange", "", map[string]any{"code": code}); ex.Code != http.StatusNotFound {
		t.Fatalf("replayed exchange = %d, want 404", ex.Code)
	}

	// The legacy /auth/google/exchange alias serves Apple handoff codes too
	// (the 'sso' token carries no provider tag).
	state2, cookie2 := startApple(t)
	rec2 := appleCallback(t, url.Values{"code": {"fake-auth-code"}, "state": {state2}}, cookie2)
	loc2 := rec2.Header().Get("Location")
	code2 := loc2[strings.LastIndex(loc2, "/")+1:]
	if ex := doJSON(t, "POST", "/api/v1/auth/google/exchange", "", map[string]any{"code": code2}); ex.Code != http.StatusOK {
		t.Fatalf("google-alias exchange of apple code = %d, want 200", ex.Code)
	}
}

func TestAppleClientSecretJWT(t *testing.T) {
	// Unit test: valid ES256 JWT with raw r||s signature and 5-minute expiry.
	// setupFakeApple's token server also verifies this on every exchange; this
	// pins the details deterministically.
	setupFakeApple(t, testAppleClaims("unit@apple-example.com")) // provides key env
	now := time.Unix(1_770_000_000, 0)
	secret, err := appleClientSecret(now)
	if err != nil {
		t.Fatalf("appleClientSecret: %v", err)
	}
	parts := strings.Split(secret, ".")
	if len(parts) != 3 {
		t.Fatalf("not a JWT: %q", secret)
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decode payload: %v", err)
	}
	var claims struct{ Iat, Exp int64 }
	if err := json.Unmarshal(payload, &claims); err != nil {
		t.Fatalf("claims: %v", err)
	}
	if claims.Exp-claims.Iat != 300 {
		t.Fatalf("exp-iat = %d, want 300", claims.Exp-claims.Iat)
	}
}
