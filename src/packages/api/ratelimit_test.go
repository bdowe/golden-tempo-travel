package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIPRateLimiterAllowsBurstThenBlocks(t *testing.T) {
	l := newIPRateLimiter(60, 3)
	for i := 0; i < 3; i++ {
		if !l.allow("1.2.3.4") {
			t.Fatalf("request %d within burst should be allowed", i+1)
		}
	}
	if l.allow("1.2.3.4") {
		t.Fatal("request beyond burst should be blocked")
	}
	// A different IP has its own bucket.
	if !l.allow("5.6.7.8") {
		t.Fatal("distinct IP should not share the exhausted bucket")
	}
}

func TestClientIPPrefersRightmostForwardedFor(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "172.18.0.5:52000"
	r.Header.Set("X-Forwarded-For", "203.0.113.7, 198.51.100.2")
	if got := clientIP(r); got != "198.51.100.2" {
		t.Fatalf("clientIP = %q, want rightmost XFF entry 198.51.100.2", got)
	}
}

func TestClientIPFallsBackToRemoteAddr(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "192.0.2.9:41234"
	if got := clientIP(r); got != "192.0.2.9" {
		t.Fatalf("clientIP = %q, want RemoteAddr host 192.0.2.9", got)
	}
}

func TestRateLimitMiddlewareReturns429(t *testing.T) {
	l := newIPRateLimiter(60, 1)
	handler := rateLimitMiddleware(l)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	first := httptest.NewRecorder()
	handler.ServeHTTP(first, httptest.NewRequest(http.MethodGet, "/", nil))
	if first.Code != http.StatusOK {
		t.Fatalf("first request status = %d, want 200", first.Code)
	}

	second := httptest.NewRecorder()
	handler.ServeHTTP(second, httptest.NewRequest(http.MethodGet, "/", nil))
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("second request status = %d, want 429", second.Code)
	}
	if second.Header().Get("Retry-After") == "" {
		t.Fatal("429 response should carry Retry-After")
	}
}
