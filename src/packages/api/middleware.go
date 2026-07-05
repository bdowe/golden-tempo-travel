package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/google/uuid"
)

const requestIDContextKey contextKey = "request_id"

// requestIDFromContext returns the request ID stamped by requestIDMiddleware,
// or "" outside a request.
func requestIDFromContext(ctx context.Context) string {
	id, _ := ctx.Value(requestIDContextKey).(string)
	return id
}

// ctxLog returns a logger pre-tagged with the request ID, for handlers that
// want correlated log lines. Falls back to the default logger untagged.
func ctxLog(ctx context.Context) *slog.Logger {
	if id := requestIDFromContext(ctx); id != "" {
		return slog.Default().With("request_id", id)
	}
	return slog.Default()
}

// statusRecorder captures the response status for the request log. It must
// forward Flush: the SSE /plan handler type-asserts http.Flusher on the
// writer it receives, and losing that capability here would break streaming.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Flush() {
	if f, ok := s.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

// requestIDMiddleware assigns each request an ID (honoring an inbound
// X-Request-ID from the gateway), echoes it on the response, and emits the
// structured request log line.
func requestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" || len(id) > 128 {
			id = uuid.NewString()
		}
		w.Header().Set("X-Request-ID", id)

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		start := time.Now()
		next.ServeHTTP(rec, r.WithContext(context.WithValue(r.Context(), requestIDContextKey, id)))

		slog.Info("request",
			"request_id", id,
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote", clientIP(r),
		)
	})
}

// recoveryMiddleware converts a handler panic into a JSON 500 instead of a
// dropped connection, logging the stack with the request ID. net/http already
// keeps the process alive on handler panics; the value here is the clean
// response and the structured log. For a stream that has already committed
// headers (SSE), the 500 write is a harmless no-op on the wire.
func recoveryMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			rec := recover()
			if rec == nil {
				return
			}
			if rec == http.ErrAbortHandler {
				// net/http uses this sentinel to abort silently; preserve it.
				panic(rec)
			}
			slog.Error("panic recovered",
				"request_id", requestIDFromContext(r.Context()),
				"method", r.Method,
				"path", r.URL.Path,
				"panic", fmt.Sprint(rec),
				"stack", string(debug.Stack()),
			)
			writeJSONError(w, http.StatusInternalServerError, "internal server error")
		}()
		next.ServeHTTP(w, r)
	})
}
