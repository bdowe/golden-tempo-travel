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

// notificationsOfType polls the per-user feed (the writers are fire-and-forget
// goroutines) and returns the rows of a given type. Polls briefly so the
// background insert has time to land before we assert.
func notificationsOfType(t *testing.T, userID uuid.UUID, typ string) []store.Notification {
	t.Helper()
	var last []store.Notification
	deadline := time.Now().Add(2 * time.Second)
	for {
		rows, err := store.New(dbPool).ListNotificationsByUser(context.Background(),
			store.ListNotificationsByUserParams{UserID: userID, Limit: 100})
		if err != nil {
			t.Fatalf("list notifications: %v", err)
		}
		last = last[:0]
		for _, r := range rows {
			if r.Type == typ {
				last = append(last, r)
			}
		}
		if len(last) > 0 || time.Now().After(deadline) {
			return last
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// countNotificationsOfType is notificationsOfType without the wait — for
// asserting that NO notification landed (e.g. the actor, or a solo owner).
func countNotificationsOfType(t *testing.T, userID uuid.UUID, typ string) int {
	t.Helper()
	rows, err := store.New(dbPool).ListNotificationsByUser(context.Background(),
		store.ListNotificationsByUserParams{UserID: userID, Limit: 100})
	if err != nil {
		t.Fatalf("list notifications: %v", err)
	}
	n := 0
	for _, r := range rows {
		if r.Type == typ {
			n++
		}
	}
	return n
}

func TestCollabEditNotifiesOwnerAndOtherCollaborators(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	editor1, editor1Token := createTestUser(t, "editor1@example.com")
	editor2, editor2Token := createTestUser(t, "editor2@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "editor")

	if rec := joinShare(t, editor1Token, shareToken); rec.Code >= 300 {
		t.Fatalf("editor1 join = %d: %s", rec.Code, rec.Body.String())
	}
	if rec := joinShare(t, editor2Token, shareToken); rec.Code >= 300 {
		t.Fatalf("editor2 join = %d: %s", rec.Code, rec.Body.String())
	}

	// editor1 edits the shared trip → owner and editor2 get one collab_edit
	// each; editor1 (the actor) gets none.
	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", editor1Token, map[string]any{
		"name": "Editor1 Pick", "latitude": 37.98, "longitude": 23.73,
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("editor1 add item = %d: %s", add.Code, add.Body.String())
	}

	ownerNotes := notificationsOfType(t, owner.ID, "collab_edit")
	if len(ownerNotes) != 1 {
		t.Fatalf("owner collab_edit = %d, want 1", len(ownerNotes))
	}
	if editor2Notes := notificationsOfType(t, editor2.ID, "collab_edit"); len(editor2Notes) != 1 {
		t.Fatalf("editor2 collab_edit = %d, want 1", len(editor2Notes))
	}
	if actorNotes := countNotificationsOfType(t, editor1.ID, "collab_edit"); actorNotes != 0 {
		t.Fatalf("actor (editor1) collab_edit = %d, want 0", actorNotes)
	}
	// Payload carries actor_name + trip_title, trip_id links the row.
	if got := string(ownerNotes[0].Payload); got == "" || got == "{}" {
		t.Fatalf("owner collab_edit payload empty: %q", got)
	}
	if !ownerNotes[0].TripID.Valid || uuid.UUID(ownerNotes[0].TripID.Bytes) != trip.ID {
		t.Fatalf("owner collab_edit trip_id mismatch")
	}

	// A second edit by the same actor within the 6h window is throttled: no
	// duplicate for either recipient.
	add2 := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", editor1Token, map[string]any{
		"name": "Editor1 Pick 2", "latitude": 37.99, "longitude": 23.74,
	})
	if add2.Code != http.StatusCreated && add2.Code != http.StatusOK {
		t.Fatalf("editor1 second add = %d: %s", add2.Code, add2.Body.String())
	}
	// Give the (throttled) goroutine time to run and prove it inserted nothing.
	time.Sleep(300 * time.Millisecond)
	if n := countNotificationsOfType(t, owner.ID, "collab_edit"); n != 1 {
		t.Fatalf("owner collab_edit after throttle = %d, want 1", n)
	}
	if n := countNotificationsOfType(t, editor2.ID, "collab_edit"); n != 1 {
		t.Fatalf("editor2 collab_edit after throttle = %d, want 1", n)
	}

	// The OWNER editing the shared trip notifies no one (trigger is a
	// non-owner actor).
	ownerEdit := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", ownerToken, map[string]any{
		"name": "Owner Pick", "latitude": 38.00, "longitude": 23.75,
	})
	if ownerEdit.Code != http.StatusCreated && ownerEdit.Code != http.StatusOK {
		t.Fatalf("owner add item = %d: %s", ownerEdit.Code, ownerEdit.Body.String())
	}
	time.Sleep(300 * time.Millisecond)
	if n := countNotificationsOfType(t, editor1.ID, "collab_edit"); n != 0 {
		t.Fatalf("editor1 collab_edit after owner edit = %d, want 0", n)
	}
	if n := countNotificationsOfType(t, editor2.ID, "collab_edit"); n != 1 {
		t.Fatalf("editor2 collab_edit after owner edit = %d, want 1 (unchanged)", n)
	}
}

func TestSoloOwnerEditNotifiesNoOne(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "solo@example.com")
	trip := createTestTrip(t, owner.ID, 1)

	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", ownerToken, map[string]any{
		"name": "Solo Pick", "latitude": 37.98, "longitude": 23.73,
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("solo owner add item = %d: %s", add.Code, add.Body.String())
	}
	time.Sleep(300 * time.Millisecond)
	if n := countNotificationsOfType(t, owner.ID, "collab_edit"); n != 0 {
		t.Fatalf("solo owner collab_edit = %d, want 0", n)
	}
}

func TestInviteAcceptNotifiesOwner(t *testing.T) {
	resetDB(t)
	owner, _ := createTestUser(t, "owner@example.com")
	friend, friendToken := createTestUser(t, "friend@example.com")
	trip := createTestTripInLineage(t, owner.ID, "chat-notify-invite", "Athens")
	insertInvite(t, owner, "chat-notify-invite", "friend-work@example.com",
		"notify-invite-token", time.Now().Add(inviteTokenTTL))

	accept := doJSON(t, "POST", "/api/v1/invites/notify-invite-token/accept", friendToken, nil)
	if accept.Code != http.StatusOK {
		t.Fatalf("accept = %d: %s", accept.Code, accept.Body.String())
	}

	notes := notificationsOfType(t, owner.ID, "invite_accepted")
	if len(notes) != 1 {
		t.Fatalf("owner invite_accepted = %d, want 1", len(notes))
	}
	if !notes[0].TripID.Valid || uuid.UUID(notes[0].TripID.Bytes) != trip.ID {
		t.Fatalf("invite_accepted trip_id mismatch")
	}
	// The accepter (friend) should not be notified.
	if n := countNotificationsOfType(t, friend.ID, "invite_accepted"); n != 0 {
		t.Fatalf("accepter invite_accepted = %d, want 0", n)
	}
}

func TestShareJoinNotifiesOwnerOnce(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	viewer, viewerToken := createTestUser(t, "viewer@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	shareToken := createShare(t, ownerToken, trip.ID.String(), "viewer")

	if rec := joinShare(t, viewerToken, shareToken); rec.Code != http.StatusOK {
		t.Fatalf("join = %d: %s", rec.Code, rec.Body.String())
	}
	time.Sleep(300 * time.Millisecond)

	notes := notificationsOfType(t, owner.ID, "share_joined")
	if len(notes) != 1 {
		t.Fatalf("owner share_joined = %d, want 1", len(notes))
	}
	if !notes[0].TripID.Valid || uuid.UUID(notes[0].TripID.Bytes) != trip.ID {
		t.Fatalf("share_joined trip_id mismatch")
	}
	var payload map[string]string
	if err := json.Unmarshal(notes[0].Payload, &payload); err != nil {
		t.Fatalf("share_joined payload: %v", err)
	}
	if payload["role"] != "viewer" {
		t.Fatalf("share_joined role = %q, want viewer", payload["role"])
	}
	// The joiner is not notified.
	if n := countNotificationsOfType(t, viewer.ID, "share_joined"); n != 0 {
		t.Fatalf("joiner share_joined = %d, want 0", n)
	}

	// Re-redeeming the link is idempotent and must NOT re-notify.
	if rec := joinShare(t, viewerToken, shareToken); rec.Code != http.StatusOK {
		t.Fatalf("re-join = %d: %s", rec.Code, rec.Body.String())
	}
	time.Sleep(300 * time.Millisecond)
	if n := countNotificationsOfType(t, owner.ID, "share_joined"); n != 1 {
		t.Fatalf("owner share_joined after re-join = %d, want 1 (unchanged)", n)
	}

	// An owner opening their own link never notifies.
	if rec := joinShare(t, ownerToken, shareToken); rec.Code != http.StatusOK {
		t.Fatalf("owner self-join = %d: %s", rec.Code, rec.Body.String())
	}
	time.Sleep(300 * time.Millisecond)
	if n := countNotificationsOfType(t, owner.ID, "share_joined"); n != 1 {
		t.Fatalf("owner share_joined after self-join = %d, want 1 (unchanged)", n)
	}
}
