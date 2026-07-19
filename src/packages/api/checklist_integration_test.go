package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func decodeChecklist(t *testing.T, rec *httptest.ResponseRecorder) []map[string]any {
	t.Helper()
	var list []map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatalf("decode checklist %q: %v", rec.Body.String(), err)
	}
	return list
}

func TestChecklistCRUD(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	// Empty to start.
	rec := doJSON(t, "GET", "/api/v1/trips/"+tripID+"/checklist", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("initial list = %d: %s", rec.Code, rec.Body.String())
	}
	if len(decodeChecklist(t, rec)) != 0 {
		t.Fatalf("new trip has checklist items: %s", rec.Body.String())
	}

	// Create (category defaults to general when omitted).
	rec = doJSON(t, "POST", "/api/v1/trips/"+tripID+"/checklist", token, map[string]any{"title": "Passport", "category": "documents"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create = %d: %s", rec.Code, rec.Body.String())
	}
	created := decode(t, rec)
	itemID := created["id"].(string)
	if created["category"] != "documents" || created["title"] != "Passport" ||
		created["checked"] != false || created["auto"] != false {
		t.Fatalf("created row wrong: %v", created)
	}

	rec = doJSON(t, "POST", "/api/v1/trips/"+tripID+"/checklist", token, map[string]any{"title": "Sunscreen"})
	if rec.Code != http.StatusCreated || decode(t, rec)["category"] != "general" {
		t.Fatalf("default category = %d: %s", rec.Code, rec.Body.String())
	}

	// List shows both.
	rec = doJSON(t, "GET", "/api/v1/trips/"+tripID+"/checklist", token, nil)
	if list := decodeChecklist(t, rec); len(list) != 2 {
		t.Fatalf("list len = %d, want 2: %s", len(list), rec.Body.String())
	}

	// Toggle checked + rename + recategorize (partial PATCH).
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/checklist/"+itemID, token, map[string]any{"checked": true})
	if rec.Code != http.StatusOK || decode(t, rec)["checked"] != true {
		t.Fatalf("toggle = %d: %s", rec.Code, rec.Body.String())
	}
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/checklist/"+itemID, token, map[string]any{"title": "Passport + copies", "category": "general"})
	got := decode(t, rec)
	if got["title"] != "Passport + copies" || got["category"] != "general" || got["checked"] != true {
		t.Fatalf("partial patch clobbered/failed: %v", got)
	}

	// Delete, then it's gone (idempotent 404 on re-delete).
	rec = doJSON(t, "DELETE", "/api/v1/trips/"+tripID+"/checklist/"+itemID, token, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete = %d: %s", rec.Code, rec.Body.String())
	}
	rec = doJSON(t, "DELETE", "/api/v1/trips/"+tripID+"/checklist/"+itemID, token, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("re-delete = %d, want 404", rec.Code)
	}
	rec = doJSON(t, "GET", "/api/v1/trips/"+tripID+"/checklist", token, nil)
	if len(decodeChecklist(t, rec)) != 1 {
		t.Fatalf("list after delete = %s", rec.Body.String())
	}
}

func TestChecklistValidation(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()

	rec := doJSON(t, "POST", "/api/v1/trips/"+tripID+"/checklist", token, map[string]any{"title": "seed"})
	itemID := decode(t, rec)["id"].(string)

	cases := []struct {
		name   string
		method string
		path   string
		body   map[string]any
		want   int
	}{
		{"missing title", "POST", "/checklist", map[string]any{"category": "clothing"}, http.StatusBadRequest},
		{"blank title", "POST", "/checklist", map[string]any{"title": "  "}, http.StatusBadRequest},
		{"bad category", "POST", "/checklist", map[string]any{"title": "x", "category": "toiletries"}, http.StatusBadRequest},
		{"empty patch", "PATCH", "/checklist/" + itemID, map[string]any{}, http.StatusBadRequest},
		{"patch blank title", "PATCH", "/checklist/" + itemID, map[string]any{"title": " "}, http.StatusBadRequest},
		{"patch bad category", "PATCH", "/checklist/" + itemID, map[string]any{"category": "misc"}, http.StatusBadRequest},
		{"patch unknown id", "PATCH", "/checklist/" + uuid.NewString(), map[string]any{"checked": true}, http.StatusNotFound},
	}
	for _, tc := range cases {
		rec := doJSON(t, tc.method, "/api/v1/trips/"+tripID+tc.path, token, tc.body)
		if rec.Code != tc.want {
			t.Fatalf("%s = %d, want %d: %s", tc.name, rec.Code, tc.want, rec.Body.String())
		}
	}
}

func TestChecklistOwnershipAndAccess(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()
	rec := doJSON(t, "POST", "/api/v1/trips/"+tripID+"/checklist", token, map[string]any{"title": "Passport"})
	itemID := decode(t, rec)["id"].(string)

	// A stranger (no share) is 404 on every route.
	_, strangerToken := createTestUser(t, "stranger@example.com")
	for _, m := range []struct {
		method, path string
		body         map[string]any
	}{
		{"GET", "/checklist", nil},
		{"POST", "/checklist", map[string]any{"title": "sneak"}},
		{"PATCH", "/checklist/" + itemID, map[string]any{"checked": true}},
		{"DELETE", "/checklist/" + itemID, nil},
	} {
		if rec := doJSON(t, m.method, "/api/v1/trips/"+tripID+m.path, strangerToken, m.body); rec.Code != http.StatusNotFound {
			t.Fatalf("stranger %s %s = %d, want 404", m.method, m.path, rec.Code)
		}
	}

	// A viewer-collaborator can read but not mutate (editableTrip => 404).
	_, viewerToken := createTestUser(t, "viewer@example.com")
	shareToken := createShare(t, token, tripID, "viewer")
	if rec := joinShare(t, viewerToken, shareToken); rec.Code != http.StatusOK {
		t.Fatalf("viewer join = %d: %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/checklist/"+itemID, viewerToken, map[string]any{"checked": true}); rec.Code != http.StatusNotFound {
		t.Fatalf("viewer patch = %d, want 404", rec.Code)
	}

	// An editor-collaborator can mutate.
	_, editorToken := createTestUser(t, "editor@example.com")
	editShare := createShare(t, token, tripID, "editor")
	if rec := joinShare(t, editorToken, editShare); rec.Code != http.StatusOK {
		t.Fatalf("editor join = %d: %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+tripID+"/checklist/"+itemID, editorToken, map[string]any{"checked": true}); rec.Code != http.StatusOK {
		t.Fatalf("editor patch = %d, want 200: %s", rec.Code, rec.Body.String())
	}

	// Anonymous is 401.
	if rec := doJSON(t, "GET", "/api/v1/trips/"+tripID+"/checklist", "", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous list = %d, want 401", rec.Code)
	}
}

func TestChecklistCascadeOnTripDelete(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 0)
	tripID := trip.ID.String()
	doJSON(t, "POST", "/api/v1/trips/"+tripID+"/checklist", token, map[string]any{"title": "Passport"})
	doJSON(t, "POST", "/api/v1/trips/"+tripID+"/checklist", token, map[string]any{"title": "Adapter", "category": "electronics"})

	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+tripID, token, nil); rec.Code != http.StatusNoContent && rec.Code != http.StatusOK {
		t.Fatalf("delete trip = %d: %s", rec.Code, rec.Body.String())
	}
	var n int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*) FROM trip_checklist_items WHERE trip_id = $1`, trip.ID).Scan(&n); err != nil {
		t.Fatalf("count: %v", err)
	}
	if n != 0 {
		t.Fatalf("checklist rows survived trip delete: %d", n)
	}
}

// TestAddPackingItemToolSeedsAutoRows checks the /plan agent tool inserts a
// row (auto=true) on an owned trip, emits trip_updated, and fails closed for
// non-owners — the interactive AI-seeding path.
func TestAddPackingItemToolSeedsAutoRows(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "agent@example.com")
	other, _ := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	s, rec := testPlanSession(true, owner.ID)
	msg, isErr := runAddPackingItemTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","title":"Rain jacket","category":"clothing"}`))
	if isErr || !strings.Contains(msg, "Rain jacket") {
		t.Fatalf("add = %q (err=%v)", msg, isErr)
	}
	if !strings.Contains(rec.Body.String(), "trip_updated") {
		t.Fatal("add_packing_item did not emit trip_updated")
	}

	// Persisted as an auto row, visible via the REST checklist endpoint.
	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/checklist", ownerToken, nil)
	items := decodeChecklist(t, list)
	if len(items) != 1 || items[0]["title"] != "Rain jacket" ||
		items[0]["category"] != "clothing" || items[0]["auto"] != true {
		t.Fatalf("seeded row wrong: %s", list.Body.String())
	}

	// Category defaults to general when omitted.
	if _, isErr := runAddPackingItemTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","title":"Travel insurance"}`)); isErr {
		t.Fatal("default-category add errored")
	}
	var cat string
	if err := dbPool.QueryRow(context.Background(),
		`SELECT category FROM trip_checklist_items WHERE trip_id = $1 AND title = 'Travel insurance'`, trip.ID).Scan(&cat); err != nil || cat != "general" {
		t.Fatalf("default category = %q (err=%v)", cat, err)
	}

	// Cross-user write must fail closed.
	otherS, _ := testPlanSession(true, other.ID)
	if _, isErr := runAddPackingItemTool(otherS,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","title":"Hijack"}`)); !isErr {
		t.Fatal("cross-user add_packing_item did not error")
	}

	// Anonymous and bad category rejected.
	anon, _ := testPlanSession(false, uuid.Nil)
	if _, isErr := runAddPackingItemTool(anon, json.RawMessage(`{}`)); !isErr {
		t.Fatal("anonymous add_packing_item accepted")
	}
	if _, isErr := runAddPackingItemTool(s,
		json.RawMessage(`{"trip_id":"`+trip.ID.String()+`","title":"x","category":"toiletries"}`)); !isErr {
		t.Fatal("bad category accepted")
	}
}
