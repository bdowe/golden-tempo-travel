package main

import (
	"context"
	"encoding/json"
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

// A joined editor can run the trip-bound refine agent: the section rewrite
// lands on the owner's same trip row — no fork, no new version, and the owner
// still reads the result.
func TestCollaboratorCanRefineViaAgent(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t,
		toolTurn("update_itinerary_section", `{"scope":"trip","items":[{"name":"Editor Cafe","latitude":37.98,"longitude":23.74,"day":1}]}`),
		textTurn("Swapped the plan for the cafe."))

	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	rec := doJSON(t, "POST", "/api/v1/plan", editorToken, PlanRequest{
		TripID:   trip.ID.String(),
		Messages: []PlanChatMessage{{Role: "user", Content: "replace everything with one cafe"}},
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("/plan = %d, want 200", rec.Code)
	}
	events := planEvents(t, rec.Body.String())
	if updated := eventsOfType(events, "trip_updated"); len(updated) != 1 {
		t.Fatalf("trip_updated events = %v, want exactly one", updated)
	}
	if errs := eventsOfType(events, "error"); len(errs) != 0 {
		t.Fatalf("unexpected error events: %v", errs)
	}
	// A bound session must never create a new trip version — least of all one
	// forked under the collaborator's account.
	var tripCount int
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*) FROM trips`).Scan(&tripCount); err != nil {
		t.Fatalf("trips query: %v", err)
	}
	if tripCount != 1 {
		t.Fatalf("trips after collaborator refine = %d, want 1", tripCount)
	}
	var count int
	var name string
	if err := dbPool.QueryRow(context.Background(),
		`SELECT count(*), min(name) FROM itinerary_items WHERE trip_id = $1`,
		trip.ID).Scan(&count, &name); err != nil {
		t.Fatalf("items query: %v", err)
	}
	if count != 1 || name != "Editor Cafe" {
		t.Fatalf("items after refine = %d/%q, want 1/\"Editor Cafe\"", count, name)
	}
	// The owner still owns and reads the refined trip.
	get := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil)
	if get.Code != http.StatusOK {
		t.Fatalf("owner GET after collaborator refine = %d", get.Code)
	}
}

// A non-member is refused the trip-bound agent before anything streams.
func TestStrangerCannotRefineViaAgent(t *testing.T) {
	resetDB(t)
	newFakeAnthropic(t, textTurn("should never be reached"))

	owner, _ := createTestUser(t, "owner@example.com")
	_, strangerToken := createTestUser(t, "stranger@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	rec := doJSON(t, "POST", "/api/v1/plan", strangerToken, PlanRequest{
		TripID:   trip.ID.String(),
		Messages: []PlanChatMessage{{Role: "user", Content: "rewrite this trip"}},
	})
	events := planEvents(t, rec.Body.String())
	if errs := eventsOfType(events, "error"); len(errs) != 1 {
		t.Fatalf("error events = %v, want exactly one", errs)
	}
	if updated := eventsOfType(events, "trip_updated"); len(updated) != 0 {
		t.Fatalf("stranger produced trip_updated: %v", updated)
	}
}

// The collaborator's editor chat_id exposure: shared trips must not leak the
// owner's plan-session key (a collaborator seeding /plan with it would fork
// the lineage under their own account).
func TestCollaboratorResponsesOmitChatID(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	get := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), editorToken, nil)
	if get.Code != http.StatusOK {
		t.Fatalf("editor GET = %d", get.Code)
	}
	if body := decode(t, get); body["chat_id"] != nil {
		t.Fatalf("editor GET leaks chat_id: %v", body["chat_id"])
	}
	// Owner keeps seeing it (their own plan-session key).
	ownerGet := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String(), ownerToken, nil)
	if body := decode(t, ownerGet); body["chat_id"] == nil {
		t.Fatalf("owner GET lost chat_id")
	}

	shared := doJSON(t, "GET", "/api/v1/trips/shared-with-me", editorToken, nil)
	if shared.Code != http.StatusOK {
		t.Fatalf("shared-with-me = %d", shared.Code)
	}
	var rows []map[string]any
	if err := json.Unmarshal(shared.Body.Bytes(), &rows); err != nil {
		t.Fatalf("shared-with-me decode: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("shared-with-me rows = %d, want 1", len(rows))
	}
	for _, row := range rows {
		if row["chat_id"] != nil {
			t.Fatalf("shared-with-me leaks chat_id: %v", row["chat_id"])
		}
	}
}
