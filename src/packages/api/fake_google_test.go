package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// Fake Google token endpoint, pointed at via the GOOGLE_OAUTH_TOKEN_URL env
// seam (same idea as the fake-Anthropic harness). The id_token it mints is
// unsigned — fine, because the server validates claims, not signatures, for
// tokens received directly from the (faked) token endpoint.

const testGoogleClientID = "test-client-id.apps.googleusercontent.com"

// fakeIDToken builds header.payload.signature with an unverifiable signature.
func fakeIDToken(t *testing.T, claims googleClaims) string {
	t.Helper()
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`))
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatalf("marshal claims: %v", err)
	}
	return header + "." + base64.RawURLEncoding.EncodeToString(payload) + ".x"
}

// testGoogleClaims returns a valid claim set; tests tweak fields per case.
func testGoogleClaims(email, name string) googleClaims {
	return googleClaims{
		Iss:           "https://accounts.google.com",
		Aud:           testGoogleClientID,
		Sub:           "google-sub-" + email,
		Email:         email,
		EmailVerified: true,
		Name:          name,
		Exp:           time.Now().Add(time.Hour).Unix(),
	}
}

// setupFakeGoogle configures the OAuth env and serves a token endpoint that
// answers every exchange with an id_token carrying the given claims.
func setupFakeGoogle(t *testing.T, claims googleClaims) {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil || r.FormValue("code") == "" || r.FormValue("code_verifier") == "" {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"id_token": fakeIDToken(t, claims)})
	}))
	t.Cleanup(srv.Close)
	t.Setenv("GOOGLE_OAUTH_CLIENT_ID", testGoogleClientID)
	t.Setenv("GOOGLE_OAUTH_CLIENT_SECRET", "test-secret")
	t.Setenv("GOOGLE_OAUTH_TOKEN_URL", srv.URL)
}
