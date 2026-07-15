package main

import (
	"bytes"
	"errors"
	"io"
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

// With SENTRY_DSN unset (sentryEnabled false, hub uninitialized), a panic
// must still produce the exact JSON 500 the client always got — byte for
// byte — proving the Sentry integration is fully inert when disabled.
func TestRecoveryMiddleware500ShapeUnchangedWithoutSentry(t *testing.T) {
	if sentryEnabled {
		t.Fatal("precondition: sentryEnabled must be false in tests")
	}
	h := recoveryMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom without sentry")
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/api/v1/anything", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("Content-Type = %q, want application/json", ct)
	}
	// Exact wire shape of writeJSONError (json.Encoder adds the newline).
	want := `{"message":"internal server error","status":"error"}` + "\n"
	if rec.Body.String() != want {
		t.Fatalf("body = %q, want %q", rec.Body.String(), want)
	}
}

// When Sentry is enabled, the panic is reported — and the 500 response is
// still identical.
func TestRecoveryMiddlewareReportsPanicToSentry(t *testing.T) {
	transport := bindFakeSentry(t)
	sentryEnabled = true

	h := recoveryMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic("boom with sentry")
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/api/v1/anything", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	want := `{"message":"internal server error","status":"error"}` + "\n"
	if rec.Body.String() != want {
		t.Fatalf("body = %q, want %q", rec.Body.String(), want)
	}

	events := transport.captured()
	if len(events) == 0 {
		t.Fatal("no sentry events captured for a panic with sentry enabled")
	}
	// A string panic value surfaces as the event message (an error value
	// would surface as an Exception); accept either.
	found := false
	for _, e := range events {
		if strings.Contains(e.Message, "boom with sentry") {
			found = true
		}
		for _, ex := range e.Exception {
			if strings.Contains(ex.Value, "boom with sentry") {
				found = true
			}
		}
	}
	if !found {
		t.Fatalf("no captured event carries the panic value; got %d events", len(events))
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

func TestBodyLimitRejectsOversizedDeclaredBody(t *testing.T) {
	h := bodyLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatal("handler must not run for an over-limit declared body")
	}))

	body := bytes.NewReader(make([]byte, maxRequestBodyBytes+1))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/optimize-route", body))

	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "request body too large") {
		t.Fatalf("body = %q, want body-too-large message", rec.Body.String())
	}
}

func TestBodyLimitAllowsNormalBody(t *testing.T) {
	h := bodyLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := io.Copy(io.Discard, r.Body); err != nil {
			t.Fatalf("reading an under-limit body failed: %v", err)
		}
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/optimize-route", bytes.NewReader(make([]byte, 64<<10))))
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
}

// /plan resends the whole chat history, so it gets the wider 4 MiB lane
// (sized to exceed what the handler's own rune caps admit): a body over the
// general cap but under the plan cap must pass through.
func TestBodyLimitPlanGetsWiderLane(t *testing.T) {
	handlerRan := false
	h := bodyLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerRan = true
		if _, err := io.Copy(io.Discard, r.Body); err != nil {
			t.Fatalf("reading a 512KiB /plan body failed: %v", err)
		}
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/plan", bytes.NewReader(make([]byte, 512<<10))))
	if !handlerRan || rec.Code != http.StatusOK {
		t.Fatalf("handlerRan = %v, status = %d; want 512KiB /plan body to pass", handlerRan, rec.Code)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/plan", bytes.NewReader(make([]byte, planMaxRequestBodyBytes+1))))
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413 for over-cap /plan body", rec.Code)
	}
}

// /transcribe carries a recorded audio clip, so it gets the 10 MiB lane: a
// body over the general 256 KiB cap must pass, and one over the audio cap
// must still die with a 413.
func TestBodyLimitTranscribeGetsWiderLane(t *testing.T) {
	handlerRan := false
	h := bodyLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handlerRan = true
		if _, err := io.Copy(io.Discard, r.Body); err != nil {
			t.Fatalf("reading a 2MiB /transcribe body failed: %v", err)
		}
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/transcribe", bytes.NewReader(make([]byte, 2<<20))))
	if !handlerRan || rec.Code != http.StatusOK {
		t.Fatalf("handlerRan = %v, status = %d; want 2MiB /transcribe body to pass", handlerRan, rec.Code)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/transcribe", bytes.NewReader(make([]byte, transcribeMaxRequestBytes+1))))
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413 for over-cap /transcribe body", rec.Code)
	}
}

// Clients that lie about (or omit) Content-Length can't be rejected up front;
// MaxBytesReader must stop the read mid-body instead.
func TestBodyLimitStopsUndeclaredOversizedRead(t *testing.T) {
	var readErr error
	h := bodyLimitMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, readErr = io.Copy(io.Discard, r.Body)
	}))

	req := httptest.NewRequest("POST", "/api/v1/optimize-route", bytes.NewReader(make([]byte, maxRequestBodyBytes+1)))
	req.ContentLength = -1 // unknown length (e.g. chunked)
	h.ServeHTTP(httptest.NewRecorder(), req)

	var maxErr *http.MaxBytesError
	if !errors.As(readErr, &maxErr) {
		t.Fatalf("read error = %v, want *http.MaxBytesError", readErr)
	}
}

// End-to-end through buildRouter: the middleware is actually wired, and an
// oversized request dies with a 413 before reaching any handler (no DB needed).
func TestRouterRejectsOversizedBody(t *testing.T) {
	router := buildRouter()
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, httptest.NewRequest("POST", "/api/v1/optimize-route", bytes.NewReader(make([]byte, maxRequestBodyBytes+1))))
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413", rec.Code)
	}
}
