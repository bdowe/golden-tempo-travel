package main

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

func alertBody(overrides map[string]any) map[string]any {
	body := map[string]any{
		"origin":      "BOS",
		"destination": "CDG",
		"depart_date": time.Now().AddDate(0, 2, 0).Format(dateLayout),
	}
	for k, v := range overrides {
		body[k] = v
	}
	return body
}

func TestAlertCRUDFlow(t *testing.T) {
	resetDB(t)
	_, token := createTestUser(t, "watcher@example.com")

	create := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(map[string]any{
		"target_price": 450.0, "current_price": 498.0, "currency": "usd",
	}))
	if create.Code != http.StatusCreated {
		t.Fatalf("create = %d: %s", create.Code, create.Body.String())
	}
	created := decode(t, create)
	id, _ := created["id"].(string)
	if id == "" || created["status"] != "active" {
		t.Fatalf("create response wrong: %s", create.Body.String())
	}
	if created["currency"] != "USD" || created["last_checked_price"] != 498.0 {
		t.Fatalf("client baseline not stored: %s", create.Body.String())
	}

	list := doJSON(t, "GET", "/api/v1/alerts", token, nil)
	var alerts []map[string]any
	if err := json.Unmarshal(list.Body.Bytes(), &alerts); err != nil || len(alerts) != 1 {
		t.Fatalf("list = %d %s", list.Code, list.Body.String())
	}

	pause := doJSON(t, "PATCH", "/api/v1/alerts/"+id, token, map[string]any{"status": "paused"})
	if pause.Code != http.StatusOK || decode(t, pause)["status"] != "paused" {
		t.Fatalf("pause = %d: %s", pause.Code, pause.Body.String())
	}

	del := doJSON(t, "DELETE", "/api/v1/alerts/"+id, token, nil)
	if del.Code != http.StatusNoContent {
		t.Fatalf("delete = %d", del.Code)
	}
	if again := doJSON(t, "DELETE", "/api/v1/alerts/"+id, token, nil); again.Code != http.StatusNotFound {
		t.Fatalf("re-delete = %d, want 404", again.Code)
	}
}

func TestAlertDuplicateAndCap(t *testing.T) {
	resetDB(t)
	_, token := createTestUser(t, "watcher@example.com")

	if rec := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(nil)); rec.Code != http.StatusCreated {
		t.Fatalf("first create = %d: %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(nil)); rec.Code != http.StatusConflict {
		t.Fatalf("duplicate create = %d, want 409", rec.Code)
	}

	// Fill up to the cap with distinct routes, then expect 422.
	dests := []string{"NRT", "SYD", "LIS", "ATH", "JTR", "FCO", "MAD", "BER", "AMS"}
	for _, d := range dests {
		rec := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(map[string]any{"destination": d}))
		if rec.Code != http.StatusCreated {
			t.Fatalf("create %s = %d: %s", d, rec.Code, rec.Body.String())
		}
	}
	rec := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(map[string]any{"destination": "VIE"}))
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("11th alert = %d, want 422", rec.Code)
	}
}

func TestAlertClearTargetToAnyDrop(t *testing.T) {
	resetDB(t)
	_, token := createTestUser(t, "watcher@example.com")

	// Start in target mode.
	create := doJSON(t, "POST", "/api/v1/alerts", token, alertBody(map[string]any{
		"target_price": 450.0,
	}))
	if create.Code != http.StatusCreated {
		t.Fatalf("create = %d: %s", create.Code, create.Body.String())
	}
	created := decode(t, create)
	id := created["id"].(string)
	if created["target_price"] != 450.0 {
		t.Fatalf("target not set on create: %s", create.Body.String())
	}

	// clear_target:true reverts to any-drop mode (target_price = NULL).
	clear := doJSON(t, "PATCH", "/api/v1/alerts/"+id, token, map[string]any{"clear_target": true})
	if clear.Code != http.StatusOK {
		t.Fatalf("clear = %d: %s", clear.Code, clear.Body.String())
	}
	if got := decode(t, clear)["target_price"]; got != nil {
		t.Fatalf("target_price not cleared: got %v", got)
	}

	// A plain patch (no target fields) must keep it any-drop, not resurrect it.
	pause := doJSON(t, "PATCH", "/api/v1/alerts/"+id, token, map[string]any{"status": "paused"})
	if pause.Code != http.StatusOK || decode(t, pause)["target_price"] != nil {
		t.Fatalf("target reappeared after status patch: %s", pause.Body.String())
	}

	// Setting a target again after clearing works.
	reset := doJSON(t, "PATCH", "/api/v1/alerts/"+id, token, map[string]any{"target_price": 399.0})
	if reset.Code != http.StatusOK || decode(t, reset)["target_price"] != 399.0 {
		t.Fatalf("re-set target failed: %d %s", reset.Code, reset.Body.String())
	}

	// Contradictory request (clear + set) is rejected.
	both := doJSON(t, "PATCH", "/api/v1/alerts/"+id, token, map[string]any{
		"clear_target": true, "target_price": 500.0,
	})
	if both.Code != http.StatusBadRequest {
		t.Fatalf("clear+set = %d, want 400: %s", both.Code, both.Body.String())
	}
}

func TestAlertOwnershipAndAuth(t *testing.T) {
	resetDB(t)
	_, ownerToken := createTestUser(t, "owner@example.com")
	_, otherToken := createTestUser(t, "other@example.com")

	create := doJSON(t, "POST", "/api/v1/alerts", ownerToken, alertBody(nil))
	if create.Code != http.StatusCreated {
		t.Fatalf("create = %d", create.Code)
	}
	id := decode(t, create)["id"].(string)

	if rec := doJSON(t, "PATCH", "/api/v1/alerts/"+id, otherToken, map[string]any{"status": "paused"}); rec.Code != http.StatusNotFound {
		t.Fatalf("cross-user patch = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "DELETE", "/api/v1/alerts/"+id, otherToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("cross-user delete = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "POST", "/api/v1/alerts", "", alertBody(nil)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous create = %d, want 401", rec.Code)
	}
	if rec := doJSON(t, "GET", "/api/v1/alerts", "", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous list = %d, want 401", rec.Code)
	}
}
