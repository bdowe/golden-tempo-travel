package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func joinShare(t *testing.T, userToken, shareToken string) *httptest.ResponseRecorder {
	t.Helper()
	return doJSON(t, "POST", "/api/v1/shared/"+shareToken+"/join", userToken, nil)
}

func TestEditorJoinAndEdit(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")

	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d: %s", rec.Code, rec.Body.String())
	}

	// Membership grants item-level editing on the trip.
	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", editorToken, map[string]any{
		"name": "Editor's Pick", "latitude": 37.98, "longitude": 23.73,
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("editor add item = %d: %s", add.Code, add.Body.String())
	}
}

func TestViewerTokenCannotJoin(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, viewerToken := createTestUser(t, "viewer@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "viewer")

	if rec := joinShare(t, viewerToken, shareToken); rec.Code != http.StatusForbidden {
		t.Fatalf("viewer join = %d, want 403", rec.Code)
	}
}

func TestNonMemberCannotEdit(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "owner@example.com")
	_, strangerToken := createTestUser(t, "stranger@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	rec := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", strangerToken, map[string]any{
		"name": "Intrusion", "latitude": 1.0, "longitude": 1.0,
	})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("non-member add item = %d, want 404", rec.Code)
	}
}

// Membership binds to the lineage, not the link: revoking share links must
// not eject existing collaborators.
func TestMembershipSurvivesLinkRevocation(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")

	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}
	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+trip.ID.String()+"/share", ownerToken, nil); rec.Code >= 300 {
		t.Fatalf("revoke = %d", rec.Code)
	}

	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", editorToken, map[string]any{
		"name": "Still Here", "latitude": 37.98, "longitude": 23.73,
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("editor edit after revoke = %d, want success", add.Code)
	}
}

func TestCollaboratorListAndRemoval(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	editor, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/collaborators", ownerToken, nil)
	if list.Code != http.StatusOK {
		t.Fatalf("owner list collaborators = %d", list.Code)
	}

	// Non-owner cannot enumerate collaborators (404, no existence leak).
	if rec := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/collaborators", editorToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("non-owner list = %d, want 404", rec.Code)
	}

	remove := doJSON(t, "DELETE", "/api/v1/trips/"+trip.ID.String()+"/collaborators/"+editor.ID.String(), ownerToken, nil)
	if remove.Code >= 300 {
		t.Fatalf("remove collaborator = %d", remove.Code)
	}
	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", editorToken, map[string]any{
		"name": "Ghost Edit", "latitude": 1.0, "longitude": 1.0,
	})
	if add.Code != http.StatusNotFound {
		t.Fatalf("removed editor add item = %d, want 404", add.Code)
	}
}
