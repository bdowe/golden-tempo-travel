package main

import (
	"strings"
	"testing"

	"github.com/google/uuid"
)

var testUnsubSecret = []byte("test-unsubscribe-secret-0123456789")

func TestUnsubscribeToken_RoundTrip(t *testing.T) {
	for _, cat := range []string{unsubReminders, unsubNudges, unsubAll} {
		id := uuid.New()
		tok := signUnsubscribeToken(testUnsubSecret, id, cat)
		gotID, gotCat, ok := verifyUnsubscribeTokenWith(testUnsubSecret, tok)
		if !ok {
			t.Fatalf("category %q: valid token failed to verify", cat)
		}
		if gotID != id {
			t.Fatalf("category %q: user id mismatch: got %s want %s", cat, gotID, id)
		}
		if gotCat != cat {
			t.Fatalf("category mismatch: got %q want %q", gotCat, cat)
		}
	}
}

func TestUnsubscribeToken_TamperedPayloadFails(t *testing.T) {
	id := uuid.New()
	tok := signUnsubscribeToken(testUnsubSecret, id, unsubNudges)
	parts := strings.SplitN(tok, ".", 2)
	// Keep the original signature but swap in a different user's payload.
	other := signUnsubscribeToken(testUnsubSecret, uuid.New(), unsubNudges)
	tampered := strings.SplitN(other, ".", 2)[0] + "." + parts[1]
	if _, _, ok := verifyUnsubscribeTokenWith(testUnsubSecret, tampered); ok {
		t.Fatal("tampered payload verified")
	}
}

func TestUnsubscribeToken_TamperedSignatureFails(t *testing.T) {
	id := uuid.New()
	tok := signUnsubscribeToken(testUnsubSecret, id, unsubAll)
	flipped := tok[:len(tok)-1]
	if tok[len(tok)-1] == 'A' {
		flipped += "B"
	} else {
		flipped += "A"
	}
	if _, _, ok := verifyUnsubscribeTokenWith(testUnsubSecret, flipped); ok {
		t.Fatal("tampered signature verified")
	}
}

func TestUnsubscribeToken_WrongSecretFails(t *testing.T) {
	id := uuid.New()
	tok := signUnsubscribeToken(testUnsubSecret, id, unsubReminders)
	if _, _, ok := verifyUnsubscribeTokenWith([]byte("a-completely-different-secret"), tok); ok {
		t.Fatal("token verified under the wrong secret")
	}
}

func TestUnsubscribeToken_UnknownCategoryFails(t *testing.T) {
	// A validly-signed token whose category isn't one we recognize must fail —
	// guards against a widened category set on one side of a deploy.
	id := uuid.New()
	tok := signUnsubscribeToken(testUnsubSecret, id, "promotions")
	if _, _, ok := verifyUnsubscribeTokenWith(testUnsubSecret, tok); ok {
		t.Fatal("unknown category verified")
	}
}

func TestUnsubscribeToken_MalformedFails(t *testing.T) {
	for _, bad := range []string{"", "no-dot", "a.b.c", "!!!.###", "."} {
		if _, _, ok := verifyUnsubscribeTokenWith(testUnsubSecret, bad); ok {
			t.Fatalf("malformed token %q verified", bad)
		}
	}
}

func TestListUnsubscribeHeaders(t *testing.T) {
	// Empty URL => no headers (a marketing send without a link stays plain).
	if got := listUnsubscribeHeaders("  "); got != nil {
		t.Fatalf("empty url should yield nil headers, got %v", got)
	}
	url := "https://app.example.com/api/v1/unsubscribe/tok.sig"
	got := listUnsubscribeHeaders(url)
	want := []string{
		"List-Unsubscribe: <" + url + ">",
		"List-Unsubscribe-Post: List-Unsubscribe=One-Click",
	}
	if len(got) != len(want) {
		t.Fatalf("header count = %d, want %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("header[%d] = %q, want %q", i, got[i], want[i])
		}
	}

	// The full message must carry both headers, in order, above the body.
	msg := buildEmailMessage("from@x.com", "to@y.com", "Weekly ideas", "hello", got)
	if !strings.Contains(msg, "\r\nList-Unsubscribe: <"+url+">\r\n") {
		t.Fatalf("message missing List-Unsubscribe header:\n%s", msg)
	}
	if !strings.Contains(msg, "\r\nList-Unsubscribe-Post: List-Unsubscribe=One-Click\r\n\r\nhello") {
		t.Fatalf("message missing List-Unsubscribe-Post header before body:\n%s", msg)
	}
}
