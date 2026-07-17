package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/google/uuid"

	"travel-route-planner/store"
)

// insertTestAlertEvent writes one event directly (bypassing the checker) and
// returns it. occurred_at defaults to now(); tests age rows with ageEvent.
func insertTestAlertEvent(t *testing.T, alertID, userID uuid.UUID, price float64, prev *float64) store.AlertEvent {
	t.Helper()
	ev, err := store.New(dbPool).InsertAlertEvent(context.Background(), store.InsertAlertEventParams{
		AlertID: alertID, UserID: userID,
		Price: price, Currency: "USD", PreviousPrice: prev,
	})
	if err != nil {
		t.Fatalf("insert event: %v", err)
	}
	return ev
}

func ageEvent(t *testing.T, id uuid.UUID, by time.Duration) {
	t.Helper()
	if _, err := dbPool.Exec(context.Background(),
		`UPDATE alert_events SET occurred_at = occurred_at - $2::interval WHERE id = $1`,
		id, by.String()); err != nil {
		t.Fatalf("age event: %v", err)
	}
}

func decodeEventList(t *testing.T, body []byte) []map[string]any {
	t.Helper()
	var out []map[string]any
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatalf("decode event list %q: %v", body, err)
	}
	return out
}

func unreadCount(t *testing.T, token string) float64 {
	t.Helper()
	rec := doJSON(t, "GET", "/api/v1/alerts/events/unread-count", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("unread-count = %d: %s", rec.Code, rec.Body.String())
	}
	n, ok := decode(t, rec)["count"].(float64)
	if !ok {
		t.Fatalf("unread-count body wrong: %s", rec.Body.String())
	}
	return n
}

func TestAlertEventsListReadAndIsolation(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "feed-owner@example.com")
	_, otherToken := createTestUser(t, "feed-other@example.com")

	create := doJSON(t, "POST", "/api/v1/alerts", ownerToken, alertBody(map[string]any{
		"target_price": 450.0, "current_price": 498.0, "currency": "USD",
	}))
	if create.Code != http.StatusCreated {
		t.Fatalf("create alert = %d: %s", create.Code, create.Body.String())
	}
	created := decode(t, create)
	if created["baseline_price"] != 498.0 {
		t.Fatalf("baseline_price not exposed on alert: %s", create.Body.String())
	}
	alertID := uuid.MustParse(created["id"].(string))

	older := insertTestAlertEvent(t, alertID, owner.ID, 450, f64(498))
	ageEvent(t, older.ID, time.Hour)
	insertTestAlertEvent(t, alertID, owner.ID, 412, f64(450))

	list := doJSON(t, "GET", "/api/v1/alerts/events", ownerToken, nil)
	if list.Code != http.StatusOK {
		t.Fatalf("list = %d: %s", list.Code, list.Body.String())
	}
	events := decodeEventList(t, list.Body.Bytes())
	if len(events) != 2 {
		t.Fatalf("events = %d, want 2: %s", len(events), list.Body.String())
	}
	newest := events[0]
	if newest["price"] != 412.0 || events[1]["price"] != 450.0 {
		t.Fatalf("not newest-first: %s", list.Body.String())
	}
	if newest["previous_price"] != 450.0 || newest["currency"] != "USD" {
		t.Fatalf("event fields wrong: %v", newest)
	}
	// Joined alert context, no second request needed.
	if newest["origin"] != "BOS" || newest["destination"] != "CDG" ||
		newest["depart_date"] == "" || newest["alert_status"] != "active" ||
		newest["target_price"] != 450.0 {
		t.Fatalf("joined context missing: %v", newest)
	}
	if newest["read_at"] != nil {
		t.Fatalf("fresh event must be unread: %v", newest)
	}

	limited := doJSON(t, "GET", "/api/v1/alerts/events?limit=1", ownerToken, nil)
	if got := decodeEventList(t, limited.Body.Bytes()); len(got) != 1 || got[0]["price"] != 412.0 {
		t.Fatalf("limit=1 wrong: %s", limited.Body.String())
	}

	if n := unreadCount(t, ownerToken); n != 2 {
		t.Fatalf("owner unread = %v, want 2", n)
	}

	// Isolation: the other user sees nothing and cannot mark the owner's
	// events read.
	otherList := doJSON(t, "GET", "/api/v1/alerts/events", otherToken, nil)
	if got := decodeEventList(t, otherList.Body.Bytes()); len(got) != 0 {
		t.Fatalf("cross-user list leaked %d events", len(got))
	}
	if n := unreadCount(t, otherToken); n != 0 {
		t.Fatalf("cross-user unread = %v, want 0", n)
	}
	if rec := doJSON(t, "POST", "/api/v1/alerts/events/read", otherToken, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("other mark-read = %d, want 204", rec.Code)
	}
	if n := unreadCount(t, ownerToken); n != 2 {
		t.Fatalf("cross-user mark-read affected owner: unread = %v, want 2", n)
	}

	// Mark-all-read clears the badge and stamps read_at.
	if rec := doJSON(t, "POST", "/api/v1/alerts/events/read", ownerToken, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("mark-read = %d, want 204", rec.Code)
	}
	if n := unreadCount(t, ownerToken); n != 0 {
		t.Fatalf("unread after mark-read = %v, want 0", n)
	}
	after := decodeEventList(t, doJSON(t, "GET", "/api/v1/alerts/events", ownerToken, nil).Body.Bytes())
	for _, ev := range after {
		if ev["read_at"] == nil {
			t.Fatalf("event still unread after mark-all: %v", ev)
		}
	}
	// Idempotent: nothing unread is still 204.
	if rec := doJSON(t, "POST", "/api/v1/alerts/events/read", ownerToken, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("second mark-read = %d, want 204", rec.Code)
	}

	// Anonymous callers are rejected across the surface.
	for _, probe := range []struct{ method, path string }{
		{"GET", "/api/v1/alerts/events"},
		{"POST", "/api/v1/alerts/events/read"},
		{"GET", "/api/v1/alerts/events/unread-count"},
	} {
		if rec := doJSON(t, probe.method, probe.path, "", nil); rec.Code != http.StatusUnauthorized {
			t.Fatalf("anonymous %s %s = %d, want 401", probe.method, probe.path, rec.Code)
		}
	}
}

func TestAlertEventsCascadeOnAlertDelete(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "cascade@example.com")

	create := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(nil))
	if create.Code != http.StatusCreated {
		t.Fatalf("create alert = %d: %s", create.Code, create.Body.String())
	}
	id := decode(t, create)["id"].(string)
	insertTestAlertEvent(t, uuid.MustParse(id), owner.ID, 412, nil)

	if n := unreadCount(t, token); n != 1 {
		t.Fatalf("unread before delete = %v, want 1", n)
	}
	if rec := doJSON(t, "DELETE", "/api/v1/alerts/"+id, token, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("delete alert = %d, want 204", rec.Code)
	}
	if n := unreadCount(t, token); n != 0 {
		t.Fatalf("events survived alert deletion: unread = %v, want 0", n)
	}
	var count int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*) FROM alert_events`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("alert_events rows after cascade = %d (%v), want 0", count, err)
	}
}
