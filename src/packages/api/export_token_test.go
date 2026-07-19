package main

import (
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

var testExportSecret = []byte("test-export-secret-0123456789")

func TestExportToken_RoundTrip(t *testing.T) {
	id := uuid.New()
	tok := signExportToken(testExportSecret, id, time.Now().Add(time.Hour))
	got, ok := verifyExportTokenWith(testExportSecret, tok, time.Now())
	if !ok {
		t.Fatal("valid token failed to verify")
	}
	if got != id {
		t.Fatalf("trip id mismatch: got %s want %s", got, id)
	}
}

func TestExportToken_TamperedPayloadFails(t *testing.T) {
	id := uuid.New()
	tok := signExportToken(testExportSecret, id, time.Now().Add(time.Hour))
	parts := strings.SplitN(tok, ".", 2)
	if len(parts) != 2 {
		t.Fatalf("unexpected token shape %q", tok)
	}
	// Swap the payload for a different trip id but keep the original signature.
	other := signExportToken(testExportSecret, uuid.New(), time.Now().Add(time.Hour))
	tampered := strings.SplitN(other, ".", 2)[0] + "." + parts[1]
	if _, ok := verifyExportTokenWith(testExportSecret, tampered, time.Now()); ok {
		t.Fatal("tampered payload verified")
	}
}

func TestExportToken_TamperedSignatureFails(t *testing.T) {
	id := uuid.New()
	tok := signExportToken(testExportSecret, id, time.Now().Add(time.Hour))
	// Flip the last character of the signature segment.
	flipped := tok[:len(tok)-1]
	if tok[len(tok)-1] == 'A' {
		flipped += "B"
	} else {
		flipped += "A"
	}
	if _, ok := verifyExportTokenWith(testExportSecret, flipped, time.Now()); ok {
		t.Fatal("tampered signature verified")
	}
}

func TestExportToken_ExpiredFails(t *testing.T) {
	id := uuid.New()
	tok := signExportToken(testExportSecret, id, time.Now().Add(-time.Minute))
	if _, ok := verifyExportTokenWith(testExportSecret, tok, time.Now()); ok {
		t.Fatal("expired token verified")
	}
}

func TestExportToken_WrongSecretFails(t *testing.T) {
	id := uuid.New()
	tok := signExportToken(testExportSecret, id, time.Now().Add(time.Hour))
	if _, ok := verifyExportTokenWith([]byte("a-completely-different-secret"), tok, time.Now()); ok {
		t.Fatal("token verified under the wrong secret")
	}
}

func TestExportToken_MalformedFails(t *testing.T) {
	for _, bad := range []string{"", "no-dot", "a.b.c", "!!!.###", "."} {
		if _, ok := verifyExportTokenWith(testExportSecret, bad, time.Now()); ok {
			t.Fatalf("malformed token %q verified", bad)
		}
	}
}
