package main

import (
	"log/slog"
	"runtime/debug"
)

// safeGo runs fn in a new goroutine wrapped in a panic recover. A panic in a
// bare `go fn()` crashes the ENTIRE process (Go has no per-goroutine recovery),
// which for a single-host deployment means every in-flight request dies. Every
// fire-and-forget goroutine (analytics, emails, notifications, fan-out workers)
// must go through here so one bad payload can't take the server down.
//
// On panic it logs at Error level with the stack; because slog.Default() is
// wired to the Sentry handler in main.go, that log also raises a Sentry event.
// name identifies the call site in the log/alert.
func safeGo(name string, fn func()) {
	go func() {
		defer func() {
			if rec := recover(); rec != nil {
				slog.Error("panic in "+name, "err", rec, "stack", string(debug.Stack()))
			}
		}()
		fn()
	}()
}

// safeRun runs fn synchronously with the same panic recovery as safeGo. Used to
// guard the per-tick body of a long-lived background ticker loop so one bad tick
// logs and continues instead of killing the ticker (and the process) forever.
func safeRun(name string, fn func()) {
	defer func() {
		if rec := recover(); rec != nil {
			slog.Error("panic in "+name, "err", rec, "stack", string(debug.Stack()))
		}
	}()
	fn()
}
