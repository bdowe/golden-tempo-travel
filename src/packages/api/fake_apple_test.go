package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// Fake Apple token endpoint (sibling of fake_google_test.go), pointed at via
// the APPLE_TOKEN_URL env seam. Unlike the Google fake it VERIFIES the ES256
// client-secret JWT against a real in-test P-256 key — so a DER-vs-raw
// signature mistake in appleClientSecret fails loudly — and it rejects any
// request carrying code_verifier (Apple has no PKCE).

const (
	testAppleClientID = "com.goldentempotravel.web"
	testAppleTeamID   = "TESTTEAM01"
	testAppleKeyID    = "TESTKEY123"
)

// fakeAppleIDToken takes claims as a map so tests can mimic Apple's habit of
// sending booleans as the strings "true"/"false".
func fakeAppleIDToken(t *testing.T, claims map[string]any) string {
	t.Helper()
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"RS256","typ":"JWT"}`))
	payload, err := json.Marshal(claims)
	if err != nil {
		t.Fatalf("marshal claims: %v", err)
	}
	return header + "." + base64.RawURLEncoding.EncodeToString(payload) + ".x"
}

func testAppleClaims(email string) map[string]any {
	return map[string]any{
		"iss":            "https://appleid.apple.com",
		"aud":            testAppleClientID,
		"sub":            "apple-sub-" + email,
		"email":          email,
		"email_verified": true,
		"exp":            time.Now().Add(time.Hour).Unix(),
	}
}

// verifyAppleClientSecret checks the JWT the server sent as client_secret:
// ES256 header with our kid, iss/sub/aud claims, and a raw 64-byte r||s
// signature that verifies against pub.
func verifyAppleClientSecret(t *testing.T, secret string, pub *ecdsa.PublicKey) bool {
	t.Helper()
	parts := strings.Split(secret, ".")
	if len(parts) != 3 {
		return false
	}
	headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return false
	}
	var header struct{ Alg, Kid string }
	if json.Unmarshal(headerJSON, &header) != nil || header.Alg != "ES256" || header.Kid != testAppleKeyID {
		return false
	}
	claimsJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return false
	}
	var claims struct {
		Iss, Sub, Aud string
		Iat, Exp      int64
	}
	if json.Unmarshal(claimsJSON, &claims) != nil ||
		claims.Iss != testAppleTeamID || claims.Sub != testAppleClientID ||
		claims.Aud != "https://appleid.apple.com" || claims.Exp <= claims.Iat {
		return false
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil || len(sig) != 64 {
		return false
	}
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	return ecdsa.Verify(pub, sum[:], r, s)
}

// setupFakeApple configures the Apple OAuth env with a freshly generated
// P-256 key and serves a token endpoint answering with the given claims.
func setupFakeApple(t *testing.T, claims map[string]any) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	pemBytes := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if r.FormValue("code_verifier") != "" { // Apple has no PKCE
			w.WriteHeader(http.StatusBadRequest)
			return
		}
		if r.FormValue("code") == "" || r.FormValue("client_id") != testAppleClientID ||
			!verifyAppleClientSecret(t, r.FormValue("client_secret"), &key.PublicKey) {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"id_token": fakeAppleIDToken(t, claims)})
	}))
	t.Cleanup(srv.Close)

	t.Setenv("APPLE_TEAM_ID", testAppleTeamID)
	t.Setenv("APPLE_CLIENT_ID", testAppleClientID)
	t.Setenv("APPLE_KEY_ID", testAppleKeyID)
	t.Setenv("APPLE_PRIVATE_KEY", base64.StdEncoding.EncodeToString(pemBytes))
	t.Setenv("APPLE_TOKEN_URL", srv.URL)
}
