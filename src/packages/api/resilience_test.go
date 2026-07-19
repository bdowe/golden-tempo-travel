package main

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/puddle/v2"
)

// A hung Google socket must abort on the caller's context deadline rather than
// block the synchronous /plan agent loop forever. With a slow httptest server
// and a short-deadline context, the call must return promptly with a
// deadline-exceeded error — not hang until the client's 15s Timeout.
func TestSearchPlacesHonorsContextDeadline(t *testing.T) {
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-r.Context().Done(): // client hung up (deadline) — stop
		case <-time.After(3 * time.Second):
			w.Write([]byte(fakeTextSearchJSON))
		}
	}))
	defer slow.Close()

	orig := placesTextSearchURL
	placesTextSearchURL = slow.URL
	defer func() { placesTextSearchURL = orig }()

	svc := NewGooglePlacesService()
	svc.APIKey = "test-key"
	// A real client (not the fake transport) so the request actually reaches
	// the slow server; the context deadline — not the client Timeout — is what
	// we're asserting here.
	svc.Client = &http.Client{}

	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()

	start := time.Now()
	_, err := svc.SearchPlaces(ctx, "somewhere")
	elapsed := time.Since(start)

	if err == nil {
		t.Fatal("expected a deadline error, got nil (call did not honor the context)")
	}
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expected context.DeadlineExceeded in the chain, got: %v", err)
	}
	if elapsed > 2*time.Second {
		t.Fatalf("call took %s — it hung instead of cancelling on the deadline", elapsed)
	}
}

// safeGo must actually run fn.
func TestSafeGoRunsFn(t *testing.T) {
	done := make(chan struct{})
	safeGo("test-run", func() { close(done) })
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("safeGo never ran fn")
	}
}

// A panic inside a safeGo goroutine must be recovered — it must NOT crash the
// process — and subsequent safeGo calls must keep working.
func TestSafeGoRecoversPanic(t *testing.T) {
	panicked := make(chan struct{})
	safeGo("test-panic", func() {
		defer close(panicked) // runs during unwind, before safeGo's recover
		panic("boom")
	})
	<-panicked

	// If the panic had crashed the process, we'd never reach here. Prove the
	// worker pool is still usable.
	done := make(chan struct{})
	safeGo("test-after-panic", func() { close(done) })
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("process/goroutine machinery broken after a recovered panic")
	}
}

// safeRun is the synchronous guard used inside ticker loops: it must recover a
// panicking tick and return so the loop (and the process) survives.
func TestSafeRunRecoversAndContinues(t *testing.T) {
	safeRun("tick-1", func() { panic("bad tick") }) // must return, not crash

	ran := false
	safeRun("tick-2", func() { ran = true })
	if !ran {
		t.Fatal("safeRun did not run the next tick after a recovered panic")
	}
}

// dbErrorStatus is the classifier behind DB-blip -> 503. A connection-level
// failure is retryable (503); an absent row is not an outage (0, caller
// decides); a server-answered error keeps the connection alive (500).
func TestDBErrorStatusMapping(t *testing.T) {
	connRefused := &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("connection refused")}

	cases := []struct {
		name string
		err  error
		want int
	}{
		{"nil", nil, 0},
		{"no rows -> caller decides", pgx.ErrNoRows, 0},
		{"wrapped no rows", errors.New("lookup: " + pgx.ErrNoRows.Error()), http.StatusInternalServerError}, // not the sentinel
		{"server-side PgError -> 500", &pgconn.PgError{Code: "23505", Message: "dup"}, http.StatusInternalServerError},
		{"connection refused -> 503", connRefused, http.StatusServiceUnavailable},
		{"closed pool -> 503", puddle.ErrClosedPool, http.StatusServiceUnavailable},
		{"resource unavailable -> 503", puddle.ErrNotAvailable, http.StatusServiceUnavailable},
	}
	for _, c := range cases {
		if got := dbErrorStatus(c.err); got != c.want {
			t.Errorf("%s: dbErrorStatus = %d, want %d", c.name, got, c.want)
		}
	}

	// The real sentinel wrapped in a chain must still classify as no-rows.
	wrapped := errWrap("session lookup", pgx.ErrNoRows)
	if got := dbErrorStatus(wrapped); got != 0 {
		t.Errorf("wrapped pgx.ErrNoRows: dbErrorStatus = %d, want 0", got)
	}
}

func errWrap(msg string, err error) error { return &wrappedErr{msg, err} }

type wrappedErr struct {
	msg string
	err error
}

func (w *wrappedErr) Error() string { return w.msg + ": " + w.err.Error() }
func (w *wrappedErr) Unwrap() error { return w.err }

// A DB-connection failure inside authMiddleware must surface as a retryable 503
// — NOT a 401 that logs the user out on a transient Postgres blip. We point the
// pool at a dead address so the session lookup fails at connect time.
func TestAuthMiddlewareDBBlipReturns503(t *testing.T) {
	orig := dbPool
	defer func() { dbPool = orig }()

	cfg, err := pgxpool.ParseConfig("postgres://u:p@127.0.0.1:1/db?sslmode=disable")
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	cfg.ConnConfig.ConnectTimeout = 500 * time.Millisecond
	cfg.MinConns = 0
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("new pool: %v", err)
	}
	defer pool.Close()
	dbPool = pool

	h := authMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	req := httptest.NewRequest(http.MethodGet, "/protected", nil)
	req.Header.Set("Authorization", "Bearer some-token")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("auth on a DB blip returned %d, want 503 (must not log the user out)", rec.Code)
	}
}

// authMiddleware with no token is still a plain 401 — the DB-blip handling must
// not change the missing-credentials path.
func TestAuthMiddlewareMissingTokenStill401(t *testing.T) {
	orig := dbPool
	defer func() { dbPool = orig }()

	cfg, err := pgxpool.ParseConfig("postgres://u:p@127.0.0.1:1/db?sslmode=disable")
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("new pool: %v", err)
	}
	defer pool.Close()
	dbPool = pool

	h := authMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	req := httptest.NewRequest(http.MethodGet, "/protected", nil) // no Authorization
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("auth with no token returned %d, want 401", rec.Code)
	}
}

// userIDFromRequest must not silently downgrade an authenticated request to
// anonymous when the DB is unreachable — it surfaces errDBUnavailable so the
// caller can 503.
func TestUserIDFromRequestSurfacesDBBlip(t *testing.T) {
	orig := dbPool
	defer func() { dbPool = orig }()

	cfg, err := pgxpool.ParseConfig("postgres://u:p@127.0.0.1:1/db?sslmode=disable")
	if err != nil {
		t.Fatalf("parse config: %v", err)
	}
	cfg.ConnConfig.ConnectTimeout = 500 * time.Millisecond
	cfg.MinConns = 0
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("new pool: %v", err)
	}
	defer pool.Close()
	dbPool = pool

	req := httptest.NewRequest(http.MethodGet, "/plan", nil)
	req.Header.Set("Authorization", "Bearer some-token")
	_, authed, uerr := userIDFromRequest(req)
	if authed {
		t.Fatal("must not report authed on a DB blip")
	}
	if !errors.Is(uerr, errDBUnavailable) {
		t.Fatalf("expected errDBUnavailable, got %v", uerr)
	}
}
