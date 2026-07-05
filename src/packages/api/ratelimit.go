package main

import (
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// Per-IP token-bucket rate limiting. In-memory is deliberate: the API runs as
// a single instance behind the nginx gateway. A multi-instance deployment
// needs a shared store (e.g. Redis) behind the same middleware seam.

type ipLimiterEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

type ipRateLimiter struct {
	mu      sync.Mutex
	entries map[string]*ipLimiterEntry
	rate    rate.Limit
	burst   int
}

func newIPRateLimiter(perMinute float64, burst int) *ipRateLimiter {
	l := &ipRateLimiter{
		entries: make(map[string]*ipLimiterEntry),
		rate:    rate.Limit(perMinute / 60.0),
		burst:   burst,
	}
	go l.janitor()
	return l
}

func (l *ipRateLimiter) allow(ip string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	e, ok := l.entries[ip]
	if !ok {
		e = &ipLimiterEntry{limiter: rate.NewLimiter(l.rate, l.burst)}
		l.entries[ip] = e
	}
	e.lastSeen = time.Now()
	return e.limiter.Allow()
}

// janitor evicts limiters idle for 10+ minutes so the map cannot grow
// unbounded under address churn.
func (l *ipRateLimiter) janitor() {
	for range time.Tick(5 * time.Minute) {
		cutoff := time.Now().Add(-10 * time.Minute)
		l.mu.Lock()
		for ip, e := range l.entries {
			if e.lastSeen.Before(cutoff) {
				delete(l.entries, ip)
			}
		}
		l.mu.Unlock()
	}
}

// clientIP resolves the caller's address. The nginx gateway appends the real
// client to X-Forwarded-For ($proxy_add_x_forwarded_for), so the rightmost
// entry is the peer nginx actually saw and cannot be spoofed by the client;
// earlier entries can. Requests that bypass the gateway (local dev on :8080)
// have no X-Forwarded-For and fall back to RemoteAddr.
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		parts := strings.Split(xff, ",")
		if ip := strings.TrimSpace(parts[len(parts)-1]); ip != "" {
			return ip
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// rateLimitMiddleware rejects over-limit requests with 429 + Retry-After.
func rateLimitMiddleware(l *ipRateLimiter) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !l.allow(clientIP(r)) {
				log.Printf("rate limited %s %s from %s", r.Method, r.URL.Path, clientIP(r))
				w.Header().Set("Retry-After", "60")
				writeJSONError(w, http.StatusTooManyRequests, "rate limited; retry shortly")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
