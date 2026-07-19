package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Owner-private trip export tokens. The app authenticates with bearer tokens
// only (no cookies), so a plain browser navigation to an authed export URL
// would 401. Instead the owner mints a short-lived, HMAC-signed capability
// token that carries the trip id and an expiry, and the public print.html /
// calendar.ics routes verify it. The token IS the authorization — no DB row,
// no migration. These helpers are pure (no DB) so they unit-test cleanly.

// exportTokenTTL bounds how long a minted export link stays valid.
const exportTokenTTL = time.Hour

var (
	exportSecretOnce sync.Once
	exportSecret     []byte
)

// exportSigningSecret returns the HMAC key for export tokens. It prefers the
// EXPORT_SIGNING_SECRET env var (mirrors how the rest of the app reads secrets
// via os.Getenv). When unset it mints a random per-process secret so tokens
// stay unforgeable in dev; a restart invalidates outstanding links, which is
// fine given the 1h TTL. The very-unlikely rand failure falls back to a fixed
// documented dev default rather than panicking.
func exportSigningSecret() []byte {
	exportSecretOnce.Do(func() {
		if s := strings.TrimSpace(os.Getenv("EXPORT_SIGNING_SECRET")); s != "" {
			exportSecret = []byte(s)
			return
		}
		buf := make([]byte, 32)
		if _, err := rand.Read(buf); err != nil {
			exportSecret = []byte("golden-tempo-dev-export-secret-default")
			return
		}
		exportSecret = buf
	})
	return exportSecret
}

// signExportToken builds a token for tripID that expires at exp, signed with
// secret. Format: base64url(payload) + "." + base64url(HMAC-SHA256(payload)),
// where payload is the raw "<tripID>|<unix-exp>" string.
func signExportToken(secret []byte, tripID uuid.UUID, exp time.Time) string {
	payload := tripID.String() + "|" + strconv.FormatInt(exp.Unix(), 10)
	sig := hmacSign(secret, payload)
	enc := base64.RawURLEncoding.Strict()
	return enc.EncodeToString([]byte(payload)) + "." + enc.EncodeToString(sig)
}

// verifyExportTokenWith validates token against secret at time now, returning
// the trip id when the signature matches (constant-time) and the token has not
// expired. Any structural, signature, or expiry problem returns ok=false with
// no distinction — callers surface a single opaque 404.
func verifyExportTokenWith(secret []byte, token string, now time.Time) (uuid.UUID, bool) {
	parts := strings.SplitN(token, ".", 2)
	if len(parts) != 2 {
		return uuid.UUID{}, false
	}
	enc := base64.RawURLEncoding.Strict()
	payloadBytes, err := enc.DecodeString(parts[0])
	if err != nil {
		return uuid.UUID{}, false
	}
	gotSig, err := enc.DecodeString(parts[1])
	if err != nil {
		return uuid.UUID{}, false
	}
	wantSig := hmacSign(secret, string(payloadBytes))
	// Constant-time compare — never a byte-by-byte early return.
	if !hmac.Equal(gotSig, wantSig) {
		return uuid.UUID{}, false
	}
	fields := strings.SplitN(string(payloadBytes), "|", 2)
	if len(fields) != 2 {
		return uuid.UUID{}, false
	}
	exp, err := strconv.ParseInt(fields[1], 10, 64)
	if err != nil || now.Unix() >= exp {
		return uuid.UUID{}, false
	}
	id, err := uuid.Parse(fields[0])
	if err != nil {
		return uuid.UUID{}, false
	}
	return id, true
}

// hmacSign returns HMAC-SHA256(payload) under secret.
func hmacSign(secret []byte, payload string) []byte {
	mac := hmac.New(sha256.New, secret)
	mac.Write([]byte(payload))
	return mac.Sum(nil)
}

// newExportToken mints a token for tripID valid for exportTokenTTL using the
// process signing secret. Returns the token and its absolute expiry.
func newExportToken(tripID uuid.UUID) (string, time.Time) {
	exp := time.Now().Add(exportTokenTTL)
	return signExportToken(exportSigningSecret(), tripID, exp), exp
}

// verifyExportToken validates a token minted by newExportToken.
func verifyExportToken(token string) (uuid.UUID, bool) {
	return verifyExportTokenWith(exportSigningSecret(), token, time.Now())
}
