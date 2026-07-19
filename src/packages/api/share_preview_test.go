package main

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// TestSharePreviewAutoEscapes proves the OG page defends against injection: a
// trip title carrying HTML metacharacters must render escaped, never as live
// markup. html/template does this automatically — the test guards against a
// future refactor to fmt.Sprintf (which share_preview_handler.go warns off).
func TestSharePreviewAutoEscapes(t *testing.T) {
	data := sharePreviewData{
		Title:       `Trip <script>alert("x")</script> & "quotes"`,
		Description: `Rome & Naples <b>2026</b>`,
		URL:         "https://example.com/app/share/tok",
		Image:       "https://example.com/app/icons/Icon-512.png",
	}
	var buf bytes.Buffer
	if err := sharePreviewTmpl.Execute(&buf, data); err != nil {
		t.Fatalf("execute template: %v", err)
	}
	out := buf.String()

	// The raw, un-escaped script tag must never appear.
	if strings.Contains(out, "<script>alert") {
		t.Fatalf("unescaped <script> leaked into output:\n%s", out)
	}
	// Escaped forms must be present instead.
	for _, want := range []string{"&lt;script&gt;", "&amp;", "&#34;"} {
		if !strings.Contains(out, want) {
			t.Fatalf("expected escaped %q in output, got:\n%s", want, out)
		}
	}
	// The description's markup must be escaped too, not rendered as a real tag.
	if strings.Contains(out, "<b>2026</b>") {
		t.Fatalf("unescaped <b> from description leaked into output:\n%s", out)
	}
}

// TestPreviewBaseURL checks origin reconstruction from the proxy headers the
// nginx gateway sets: X-Forwarded-Proto wins for scheme, Host supplies the
// authority, and a missing proto falls back to http.
func TestPreviewBaseURL(t *testing.T) {
	cases := []struct {
		name  string
		proto string
		host  string
		want  string
	}{
		{"forwarded https", "https", "trips.example.com", "https://trips.example.com"},
		{"forwarded http", "http", "trips.example.com", "http://trips.example.com"},
		{"missing proto falls back to http", "", "localhost:3000", "http://localhost:3000"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/api/v1/share-preview/tok", nil)
			req.Host = tc.host
			if tc.proto != "" {
				req.Header.Set("X-Forwarded-Proto", tc.proto)
			}
			if got := previewBaseURL(req); got != tc.want {
				t.Fatalf("previewBaseURL = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestSharePreviewUnknownToken404 confirms an unknown/revoked token yields a
// clean 404 (same posture as sharedTripHandler), not a 500. DB-backed: the
// resolveShare lookup runs against Postgres, so the test skips without
// TEST_DATABASE_URL.
func TestSharePreviewUnknownToken404(t *testing.T) {
	requireDB(t)
	resetDB(t)

	rec := doJSON(t, "GET", "/api/v1/share-preview/no-such-token", "", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("unknown token = %d, want 404\nbody: %s", rec.Code, rec.Body.String())
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Fatalf("Content-Type = %q, want text/html", ct)
	}
}
