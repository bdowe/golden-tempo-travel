package main

import (
	"net/http"
	"testing"
)

func TestAdminRoutesRequireAdmin(t *testing.T) {
	resetDB(t)
	_, userToken := createTestUser(t, "civilian@example.com")

	paths := []string{
		"/api/v1/admin/metrics",
		"/api/v1/admin/local/sources",
		"/api/v1/admin/local/coverage",
		"/api/v1/trips/versions",
	}
	for _, p := range paths {
		if rec := doJSON(t, "GET", p, userToken, nil); rec.Code != http.StatusForbidden {
			t.Fatalf("non-admin GET %s = %d, want 403", p, rec.Code)
		}
		if rec := doJSON(t, "GET", p, "", nil); rec.Code != http.StatusUnauthorized {
			t.Fatalf("anonymous GET %s = %d, want 401", p, rec.Code)
		}
	}
}

func TestAdminMetricsForAdmin(t *testing.T) {
	resetDB(t)
	admin, adminToken := createTestUser(t, "admin@example.com")
	makeAdmin(t, admin.ID)

	rec := doJSON(t, "GET", "/api/v1/admin/metrics?days=7", adminToken, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("admin metrics = %d: %s", rec.Code, rec.Body.String())
	}
	body := decode(t, rec)
	if body["days"] != float64(7) {
		t.Fatalf("days = %v, want 7", body["days"])
	}
}
