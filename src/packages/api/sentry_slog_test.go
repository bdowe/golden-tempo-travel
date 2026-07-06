package main

import (
	"context"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/getsentry/sentry-go"
)

// recordingHandler is a minimal slog.Handler that remembers every record it
// receives, to prove the tee delegates faithfully.
type recordingHandler struct {
	mu      sync.Mutex
	records []slog.Record
}

func (h *recordingHandler) Enabled(context.Context, slog.Level) bool { return true }
func (h *recordingHandler) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.records = append(h.records, r)
	return nil
}
func (h *recordingHandler) WithAttrs([]slog.Attr) slog.Handler { return h }
func (h *recordingHandler) WithGroup(string) slog.Handler      { return h }

// fakeSentryTransport captures events instead of sending them anywhere.
type fakeSentryTransport struct {
	mu     sync.Mutex
	events []*sentry.Event
}

func (t *fakeSentryTransport) Configure(sentry.ClientOptions) {}
func (t *fakeSentryTransport) SendEvent(e *sentry.Event) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.events = append(t.events, e)
}
func (t *fakeSentryTransport) Flush(time.Duration) bool              { return true }
func (t *fakeSentryTransport) FlushWithContext(context.Context) bool { return true }
func (t *fakeSentryTransport) Close()                                {}

func (t *fakeSentryTransport) captured() []*sentry.Event {
	t.mu.Lock()
	defer t.mu.Unlock()
	return append([]*sentry.Event(nil), t.events...)
}

// bindFakeSentry initializes the global hub with a capturing transport and
// undoes everything on cleanup so other tests see an uninitialized hub.
func bindFakeSentry(t *testing.T) *fakeSentryTransport {
	t.Helper()
	transport := &fakeSentryTransport{}
	client, err := sentry.NewClient(sentry.ClientOptions{
		Dsn:       "https://public@sentry.example.com/1",
		Transport: transport,
	})
	if err != nil {
		t.Fatalf("sentry.NewClient: %v", err)
	}
	sentry.CurrentHub().BindClient(client)
	t.Cleanup(func() {
		sentry.CurrentHub().BindClient(nil)
		sentryEnabled = false
	})
	return transport
}

// Without sentry.Init, the tee must still deliver every record to the wrapped
// handler and must not panic — CaptureEvent on a client-less hub is a no-op.
func TestSentrySlogHandlerDelegatesWithoutInit(t *testing.T) {
	inner := &recordingHandler{}
	logger := slog.New(newSentrySlogHandler(inner))

	logger.Info("plain info", "k", "v")
	logger.Error("an error without sentry", "k", "v")

	if len(inner.records) != 2 {
		t.Fatalf("wrapped handler got %d records, want 2", len(inner.records))
	}
	if inner.records[1].Message != "an error without sentry" {
		t.Fatalf("second record message = %q", inner.records[1].Message)
	}
}

func TestSentrySlogHandlerForwardsErrorsToSentry(t *testing.T) {
	transport := bindFakeSentry(t)
	inner := &recordingHandler{}
	logger := slog.New(newSentrySlogHandler(inner))

	logger.Info("below threshold")
	logger.Warn("still below threshold")
	logger.With("request_id", "req-42").Error("kaboom", "detail", "oops")

	events := transport.captured()
	if len(events) != 1 {
		t.Fatalf("sentry got %d events, want 1 (error level only)", len(events))
	}
	e := events[0]
	if e.Message != "kaboom" {
		t.Fatalf("event message = %q, want kaboom", e.Message)
	}
	if e.Level != sentry.LevelError {
		t.Fatalf("event level = %q, want error", e.Level)
	}
	logCtx := e.Contexts["log"]
	if got := logCtx["detail"]; got != "oops" {
		t.Fatalf("event log-context detail = %v, want oops", got)
	}
	// request_id arrives via With (ctxLog's shape) and must become a tag.
	if got := e.Tags["request_id"]; got != "req-42" {
		t.Fatalf("event tag request_id = %q, want req-42", got)
	}
	if got := logCtx["request_id"]; got != "req-42" {
		t.Fatalf("event log-context request_id = %v, want req-42", got)
	}

	// The wrapped handler still saw all three records.
	if len(inner.records) != 3 {
		t.Fatalf("wrapped handler got %d records, want 3", len(inner.records))
	}
}
