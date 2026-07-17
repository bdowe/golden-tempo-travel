package main

import (
	"net/http"
	"testing"
)

// The freshness poll: owner and collaborators read it, strangers get the
// usual 404, and the payload attributes the last content edit.
func TestTripStatusAuthorization(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	_, strangerToken := createTestUser(t, "stranger@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	for name, tok := range map[string]string{"owner": ownerToken, "editor": editorToken} {
		rec := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/status", tok, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s status = %d, want 200", name, rec.Code)
		}
		if body := decode(t, rec); body["updated_at"] == nil {
			t.Fatalf("%s status missing updated_at: %v", name, body)
		}
	}
	if rec := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/status", strangerToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("stranger status = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/status", "", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous status = %d, want 401", rec.Code)
	}
}

// A collaborator's edit stamps updated_by; the owner sees "Updated by X" on
// the trip response and the status poll, while the editor's own view omits
// self-attribution.
func TestTripStatusAttributionAfterCollaboratorEdit(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	editor, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	// Before any collaborator edit: the owner created the trip, so their own
	// view carries no attribution line.
	before := decode(t, doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil))
	if before["updated_by_name"] != nil {
		t.Fatalf("owner sees self-attribution before edits: %v", before["updated_by_name"])
	}
	if before["shared"] != true {
		t.Fatalf("owner trip shared = %v, want true after join", before["shared"])
	}

	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", editorToken, map[string]any{
		"name": "Editor's Pick", "latitude": 37.98, "longitude": 23.73,
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("editor add item = %d", add.Code)
	}

	after := decode(t, doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil))
	if after["updated_by_name"] != "Test User" {
		t.Fatalf("owner updated_by_name = %v, want editor's display name", after["updated_by_name"])
	}
	// The editor's own view hides self-attribution.
	editorView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), editorToken, nil))
	if editorView["updated_by_name"] != nil {
		t.Fatalf("editor sees self-attribution: %v", editorView["updated_by_name"])
	}

	status := decode(t, doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/status", ownerToken, nil))
	if status["updated_by"] != editor.ID.String() {
		t.Fatalf("status updated_by = %v, want editor id", status["updated_by"])
	}
	if status["updated_by_name"] != "Test User" {
		t.Fatalf("status updated_by_name = %v", status["updated_by_name"])
	}
}

// The booking-todo sync endpoint runs on every trip load and must never
// stamp attribution — a reader is not an editor.
func TestPassiveSyncDoesNotStampAttribution(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	// The editor "loads" the trip: sync runs, no content edit.
	if rec := doJSON(t, "PUT", "/api/v1/trips/"+trip.ID.String()+"/booking-todos", editorToken, map[string]any{}); rec.Code >= 500 {
		t.Fatalf("sync = %d: %s", rec.Code, rec.Body.String())
	}

	ownerView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil))
	if ownerView["updated_by_name"] != nil {
		t.Fatalf("passive sync stamped attribution: %v", ownerView["updated_by_name"])
	}
}
