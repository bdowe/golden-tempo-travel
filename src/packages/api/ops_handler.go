package main

import "net/http"

// opsMetricsHandler is GET /api/v1/admin/ops/metrics: the live in-process
// request/latency/error rollup plus runtime process stats (ops_metrics.go).
//
// Unlike the /admin/metrics family, this endpoint has NO dbPool guard: process
// and request stats live entirely in memory, so they must render even in
// degraded mode (dbPool == nil) — that is precisely when operators need
// visibility. Admin auth is still enforced at route registration (authMiddleware
// does require the DB, which is the right trade: no session store, no admin).
func opsMetricsHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, opsMetrics.snapshot())
}
