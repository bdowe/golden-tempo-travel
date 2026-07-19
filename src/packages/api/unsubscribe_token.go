package main

import (
	"crypto/hmac"
	"crypto/rand"
	"encoding/base64"
	"os"
	"strings"
	"sync"

	"github.com/google/uuid"
)

// One-click email unsubscribe capability tokens. Like the export tokens, the
// token IS the authorization — a public GET/POST to /api/v1/unsubscribe/{token}
// verifies the HMAC signature and flips the opt-out flag, no session and no DB
// row. Unlike export tokens these carry NO expiry: an unsubscribe link printed
// in an email months ago must still work (CAN-SPAM/RFC 8058 expect indefinitely
// honorable opt-out). The signature is the only thing standing between a
// stranger and a user's preferences, so the signing secret must be stable in
// production (a per-process random dev fallback means old links break on
// restart, which is fine for local dev but never for prod). These helpers are
// pure (no DB) so they unit-test cleanly.

// Unsubscribe categories. "all" flips every opt-out flag at once (the footer
// "unsubscribe from all email" link); the per-stream links use the specific
// category so a user can silence the weekly nudge but keep trip reminders.
const (
	unsubReminders = "reminders"
	unsubNudges    = "nudges"
	unsubAll       = "all"
)

func validUnsubCategory(c string) bool {
	switch c {
	case unsubReminders, unsubNudges, unsubAll:
		return true
	}
	return false
}

var (
	unsubSecretOnce sync.Once
	unsubSecret     []byte
)

// unsubscribeSigningSecret returns the HMAC key for unsubscribe tokens. It
// prefers UNSUBSCRIBE_SIGNING_SECRET, then falls back to the shared
// EXPORT_SIGNING_SECRET (so a single "app signing secret" env satisfies both),
// and only if neither is set mints a random per-process secret. Random fallback
// keeps dev tokens unforgeable but invalidates outstanding links on restart —
// acceptable for local dev, never for prod (set the env there). The very
// unlikely rand failure falls back to a fixed documented dev default rather
// than panicking.
func unsubscribeSigningSecret() []byte {
	unsubSecretOnce.Do(func() {
		if s := strings.TrimSpace(os.Getenv("UNSUBSCRIBE_SIGNING_SECRET")); s != "" {
			unsubSecret = []byte(s)
			return
		}
		if s := strings.TrimSpace(os.Getenv("EXPORT_SIGNING_SECRET")); s != "" {
			unsubSecret = []byte(s)
			return
		}
		buf := make([]byte, 32)
		if _, err := rand.Read(buf); err != nil {
			unsubSecret = []byte("golden-tempo-dev-unsubscribe-secret-default")
			return
		}
		unsubSecret = buf
	})
	return unsubSecret
}

// signUnsubscribeToken builds a token for (userID, category) signed with secret.
// Format mirrors export tokens: base64url(payload) + "." + base64url(HMAC),
// where payload is the raw "<userID>|<category>" string. No expiry field.
func signUnsubscribeToken(secret []byte, userID uuid.UUID, category string) string {
	payload := userID.String() + "|" + category
	sig := hmacSign(secret, payload)
	enc := base64.RawURLEncoding.Strict()
	return enc.EncodeToString([]byte(payload)) + "." + enc.EncodeToString(sig)
}

// verifyUnsubscribeTokenWith validates token against secret, returning the user
// id and category when the signature matches (constant-time) and the category
// is one we recognize. Any structural, signature, or category problem returns
// ok=false with no distinction — callers surface a single opaque 404.
func verifyUnsubscribeTokenWith(secret []byte, token string) (uuid.UUID, string, bool) {
	parts := strings.SplitN(token, ".", 2)
	if len(parts) != 2 {
		return uuid.UUID{}, "", false
	}
	enc := base64.RawURLEncoding.Strict()
	payloadBytes, err := enc.DecodeString(parts[0])
	if err != nil {
		return uuid.UUID{}, "", false
	}
	gotSig, err := enc.DecodeString(parts[1])
	if err != nil {
		return uuid.UUID{}, "", false
	}
	wantSig := hmacSign(secret, string(payloadBytes))
	// Constant-time compare — never a byte-by-byte early return.
	if !hmac.Equal(gotSig, wantSig) {
		return uuid.UUID{}, "", false
	}
	fields := strings.SplitN(string(payloadBytes), "|", 2)
	if len(fields) != 2 {
		return uuid.UUID{}, "", false
	}
	category := fields[1]
	if !validUnsubCategory(category) {
		return uuid.UUID{}, "", false
	}
	id, err := uuid.Parse(fields[0])
	if err != nil {
		return uuid.UUID{}, "", false
	}
	return id, category, true
}

// newUnsubscribeToken mints a token for (userID, category) using the process
// signing secret.
func newUnsubscribeToken(userID uuid.UUID, category string) string {
	return signUnsubscribeToken(unsubscribeSigningSecret(), userID, category)
}

// verifyUnsubscribeToken validates a token minted by newUnsubscribeToken.
func verifyUnsubscribeToken(token string) (uuid.UUID, string, bool) {
	return verifyUnsubscribeTokenWith(unsubscribeSigningSecret(), token)
}

// unsubscribeURL builds the absolute public one-click link for (userID,
// category). The endpoint lives under the API prefix (/api/v1/unsubscribe/...),
// NOT under the Flutter app path — publicAppPath is "/app/" in deployment and
// would 404 the API route, the same gotcha as the export URLs.
func unsubscribeURL(userID uuid.UUID, category string) string {
	return publicBaseURL() + "/api/v1/unsubscribe/" + newUnsubscribeToken(userID, category)
}
