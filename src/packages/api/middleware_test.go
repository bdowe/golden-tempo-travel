package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestRecoveryMiddlewareReturns500JSON(t *testing.T) {
	h := recoveryMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom")
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/api/v1/anything", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.Contains(ct, "application/json") {
		t.Fatalf("Content-Type = %q, want JSON", ct)
	}
	if !strings.Contains(rec.Body.String(), "internal server error") {
		t.Fatalf("body = %q, want internal server error message", rec.Body.String())
	}
}

func TestRecoveryMiddlewareServesAfterPanic(t *testing.T) {
	calls := 0
	h := recoveryMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		if calls == 1 {
			panic("first request dies")
		}
		w.WriteHeader(http.StatusOK)
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/", nil))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("second request status = %d, want 200", rec.Code)
	}
}

func TestRecoveryMiddlewareRepanicsErrAbortHandler(t *testing.T) {
	h := recoveryMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic(http.ErrAbortHandler)
	}))

	defer func() {
		if recover() != http.ErrAbortHandler {
			t.Fatal("ErrAbortHandler was swallowed; must propagate")
		}
	}()
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/", nil))
	t.Fatal("expected panic to propagate")
}

func TestRequestIDGeneratedAndEchoed(t *testing.T) {
	var seenInCtx string
	h := requestIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seenInCtx = requestIDFromContext(r.Context())
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/", nil))

	got := rec.Header().Get("X-Request-ID")
	if got == "" {
		t.Fatal("no X-Request-ID on response")
	}
	if seenInCtx != got {
		t.Fatalf("context ID %q != header ID %q", seenInCtx, got)
	}
}

func TestRequestIDInboundReused(t *testing.T) {
	h := requestIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))

	req := httptest.NewRequest("GET", "/", nil)
	req.Header.Set("X-Request-ID", "gateway-abc-123")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if got := rec.Header().Get("X-Request-ID"); got != "gateway-abc-123" {
		t.Fatalf("X-Request-ID = %q, want inbound value reused", got)
	}
}

// The SSE /plan handler requires http.Flusher on the writer it receives; the
// status-recording wrapper must not hide it.
func TestStatusRecorderForwardsFlusher(t *testing.T) {
	var isFlusher bool
	h := requestIDMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, isFlusher = w.(http.Flusher)
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
	}))

	rec := httptest.NewRecorder() // httptest.ResponseRecorder implements Flusher
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/", nil))

	if !isFlusher {
		t.Fatal("statusRecorder does not expose http.Flusher — SSE /plan would break")
	}
	if !rec.Flushed {
		t.Fatal("Flush was not forwarded to the underlying writer")
	}
}
