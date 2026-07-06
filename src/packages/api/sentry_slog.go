package main

import (
	"context"
	"log/slog"

	"github.com/getsentry/sentry-go"
)

// sentrySlogHandler tees slog records at Error level and above to Sentry as
// events, delegating everything (including the error records themselves) to
// the wrapped handler unchanged. It is only installed when SENTRY_DSN is set
// (see initSentry in main.go); when Sentry is disabled the original handler
// is used directly, so the inert path pays zero overhead.
//
// Capture is asynchronous: sentry-go's HTTPTransport buffers and sends in the
// background. The recovery middleware flushes explicitly after a panic; plain
// error logs ride the background worker.
type sentrySlogHandler struct {
	inner slog.Handler
	attrs []slog.Attr // accumulated via WithAttrs (e.g. ctxLog's request_id)
}

func newSentrySlogHandler(inner slog.Handler) *sentrySlogHandler {
	return &sentrySlogHandler{inner: inner}
}

func (h *sentrySlogHandler) Enabled(ctx context.Context, level slog.Level) bool {
	return h.inner.Enabled(ctx, level)
}

func (h *sentrySlogHandler) Handle(ctx context.Context, r slog.Record) error {
	if r.Level >= slog.LevelError {
		event := sentry.NewEvent()
		event.Level = sentry.LevelError
		event.Message = r.Message
		attrs := make(sentry.Context, len(h.attrs)+r.NumAttrs())
		for _, a := range h.attrs {
			attrs[a.Key] = a.Value.Any()
		}
		r.Attrs(func(a slog.Attr) bool {
			attrs[a.Key] = a.Value.Any()
			return true
		})
		event.Contexts["log"] = attrs
		if id, ok := attrs["request_id"].(string); ok && id != "" {
			event.Tags["request_id"] = id
		}
		// CaptureEvent on an uninitialized hub (no bound client) is a
		// documented no-op returning nil, so this is safe even if the
		// handler is ever installed without sentry.Init.
		sentry.CurrentHub().CaptureEvent(event)
	}
	return h.inner.Handle(ctx, r)
}

func (h *sentrySlogHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	merged := make([]slog.Attr, 0, len(h.attrs)+len(attrs))
	merged = append(merged, h.attrs...)
	merged = append(merged, attrs...)
	return &sentrySlogHandler{inner: h.inner.WithAttrs(attrs), attrs: merged}
}

func (h *sentrySlogHandler) WithGroup(name string) slog.Handler {
	return &sentrySlogHandler{inner: h.inner.WithGroup(name), attrs: h.attrs}
}
