package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"travel-route-planner/store"
)

// insertInvite writes an invite row directly with a KNOWN plaintext token —
// the HTTP create path never returns the token (only its hash is stored), so
// redemption tests seed rows the same way expired-email-token tests do.
func insertInvite(t *testing.T, owner store.User, chatID, email, token string, expiresAt time.Time) store.TripInvite {
	t.Helper()
	inv, err := store.New(dbPool).CreateTripInvite(context.Background(), store.CreateTripInviteParams{
		ChatID: chatID, OwnerID: owner.ID, Email: email, Role: "editor",
		TokenHash: hashEmailToken(token), ExpiresAt: expiresAt,
	})
	if err != nil {
		t.Fatalf("insertInvite: %v", err)
	}
	return inv
}

func TestInviteCreateListRevoke(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, otherToken := createTestUser(t, "other@example.com")
	trip := createTestTrip(t, owner.ID, 1) // legacy trip: chat_id starts NULL

	create := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken,
		map[string]any{"email": "  Friend@Example.COM "})
	if create.Code != http.StatusCreated {
		t.Fatalf("create invite = %d: %s", create.Code, create.Body.String())
	}
	body := decode(t, create)
	if body["email"] != "friend@example.com" {
		t.Fatalf("invite email = %v, want normalized lowercase", body["email"])
	}
	if body["token"] != nil || body["token_hash"] != nil {
		t.Fatalf("create response leaks token material: %v", body)
	}
	inviteID, _ := body["id"].(string)

	// Creating the invite assigned a chat lineage to the legacy trip.
	dbTrip, err := store.New(dbPool).GetTripByIDAndOwner(context.Background(),
		store.GetTripByIDAndOwnerParams{ID: trip.ID, UserID: owner.ID})
	if err != nil || dbTrip.ChatID == nil {
		t.Fatalf("legacy trip did not get a chat_id: %v %v", dbTrip.ChatID, err)
	}

	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken, nil)
	if list.Code != http.StatusOK {
		t.Fatalf("list invites = %d", list.Code)
	}
	var rows []map[string]any
	if err := json.Unmarshal(list.Body.Bytes(), &rows); err != nil || len(rows) != 1 {
		t.Fatalf("pending invites = %v (err %v), want 1", rows, err)
	}

	// Non-owners get the 404 posture on every invite surface.
	if rec := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/invites", otherToken,
		map[string]any{"email": "x@example.com"}); rec.Code != http.StatusNotFound {
		t.Fatalf("non-owner create = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/invites", otherToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("non-owner list = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+trip.ID.String()+"/invites/"+inviteID, otherToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("non-owner revoke = %d, want 404", rec.Code)
	}

	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+trip.ID.String()+"/invites/"+inviteID, ownerToken, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("revoke = %d, want 204", rec.Code)
	}
	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+trip.ID.String()+"/invites/"+inviteID, ownerToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("double revoke = %d, want 404", rec.Code)
	}

	// Bad input: invalid email 400, self-invite 422.
	if rec := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken,
		map[string]any{"email": "not-an-email"}); rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid email = %d, want 400", rec.Code)
	}
	if rec := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken,
		map[string]any{"email": "owner@example.com"}); rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("self-invite = %d, want 422", rec.Code)
	}
}

func TestInviteAcceptGrantsEditorMembership(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	// The redeemer's account email deliberately differs from the invited
	// address (SSO reality) — the token is the capability.
	friend, friendToken := createTestUser(t, "friend-gmail@example.com")
	trip := createTestTripInLineage(t, owner.ID, "chat-invite-test", "Athens")
	inv := insertInvite(t, owner, "chat-invite-test", "friend-work@example.com",
		"known-invite-token", time.Now().Add(inviteTokenTTL))

	// Public preview: no auth, stripped shape.
	preview := doJSON(t, "GET", "/api/v1/invites/known-invite-token", "", nil)
	if preview.Code != http.StatusOK {
		t.Fatalf("preview = %d: %s", preview.Code, preview.Body.String())
	}
	pv := decode(t, preview)
	if pv["role"] != "editor" {
		t.Fatalf("preview role = %v", pv["role"])
	}
	tripJSON, _ := pv["trip"].(map[string]any)
	if tripJSON["chat_id"] != nil {
		t.Fatalf("preview leaks chat_id")
	}
	if tripJSON["booking_todos"] != nil {
		t.Fatalf("preview leaks booking todos")
	}

	// Accept requires auth.
	if rec := doJSON(t, "POST", "/api/v1/invites/known-invite-token/accept", "", nil); rec.Code != http.StatusUnauthorized {
		t.Fatalf("anon accept = %d, want 401", rec.Code)
	}

	accept := doJSON(t, "POST", "/api/v1/invites/known-invite-token/accept", friendToken, nil)
	if accept.Code != http.StatusOK {
		t.Fatalf("accept = %d: %s", accept.Code, accept.Body.String())
	}
	ab := decode(t, accept)
	if ab["access"] != "editor" || ab["trip_id"] != trip.ID.String() {
		t.Fatalf("accept body = %v", ab)
	}

	// Membership is real: the friend can edit through the editable seam.
	add := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/items", friendToken, map[string]any{
		"name": "Invited Pick", "latitude": 37.98, "longitude": 23.73,
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("invited editor add item = %d: %s", add.Code, add.Body.String())
	}
	collabs := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/collaborators", ownerToken, nil)
	if collabs.Code != http.StatusOK || !json.Valid(collabs.Body.Bytes()) {
		t.Fatalf("collaborators = %d", collabs.Code)
	}
	var crows []map[string]any
	_ = json.Unmarshal(collabs.Body.Bytes(), &crows)
	if len(crows) != 1 || crows[0]["user_id"] != friend.ID.String() {
		t.Fatalf("collaborators = %v, want the invited friend", crows)
	}

	// Consumed: gone from pending, dead for others, idempotent for the redeemer.
	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken, nil)
	var pending []map[string]any
	_ = json.Unmarshal(list.Body.Bytes(), &pending)
	if len(pending) != 0 {
		t.Fatalf("pending after accept = %v, want none", pending)
	}
	if rec := doJSON(t, "POST", "/api/v1/invites/known-invite-token/accept", friendToken, nil); rec.Code != http.StatusOK {
		t.Fatalf("re-accept by redeemer = %d, want 200", rec.Code)
	}
	_, thirdToken := createTestUser(t, "third@example.com")
	if rec := doJSON(t, "POST", "/api/v1/invites/known-invite-token/accept", thirdToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("accept by third party after redemption = %d, want 404", rec.Code)
	}
	if rec := doJSON(t, "GET", "/api/v1/invites/known-invite-token", "", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("preview after redemption = %d, want 404", rec.Code)
	}

	// The invite records who actually redeemed it.
	stored, err := store.New(dbPool).GetInviteByTokenHash(context.Background(), hashEmailToken("known-invite-token"))
	if err != nil || !stored.AcceptedBy.Valid || stored.AcceptedBy.Bytes != friend.ID {
		t.Fatalf("accepted_by = %v (err %v), want friend", stored.AcceptedBy, err)
	}
	_ = inv
}

func TestInviteExpiredAndRevokedAreDead(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, friendToken := createTestUser(t, "friend@example.com")
	createTestTripInLineage(t, owner.ID, "chat-dead-invites", "Naxos")

	insertInvite(t, owner, "chat-dead-invites", "a@example.com", "expired-token",
		time.Now().Add(-time.Hour))
	revoked := insertInvite(t, owner, "chat-dead-invites", "b@example.com", "revoked-token",
		time.Now().Add(inviteTokenTTL))
	if _, err := dbPool.Exec(context.Background(),
		`UPDATE trip_invites SET revoked_at = now() WHERE id = $1`, revoked.ID); err != nil {
		t.Fatalf("revoke fixture: %v", err)
	}

	for _, token := range []string{"expired-token", "revoked-token", "never-existed"} {
		if rec := doJSON(t, "GET", "/api/v1/invites/"+token, "", nil); rec.Code != http.StatusNotFound {
			t.Fatalf("preview %s = %d, want 404", token, rec.Code)
		}
		if rec := doJSON(t, "POST", "/api/v1/invites/"+token+"/accept", friendToken, nil); rec.Code != http.StatusNotFound {
			t.Fatalf("accept %s = %d, want 404", token, rec.Code)
		}
	}
	// Expired invites drop out of the pending list too.
	trip, _ := store.New(dbPool).GetLatestTripByOwnerAndChat(context.Background(),
		store.GetLatestTripByOwnerAndChatParams{UserID: owner.ID, ChatID: strPtr("chat-dead-invites")})
	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken, nil)
	var pending []map[string]any
	_ = json.Unmarshal(list.Body.Bytes(), &pending)
	if len(pending) != 0 {
		t.Fatalf("pending = %v, want none", pending)
	}
}

// Re-inviting the same address voids the earlier token and keeps exactly one
// live invite (the partial unique index makes this atomic).
func TestReinviteInvalidatesOldToken(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, friendToken := createTestUser(t, "friend@example.com")
	trip := createTestTripInLineage(t, owner.ID, "chat-reinvite", "Paros")
	insertInvite(t, owner, "chat-reinvite", "friend@example.com", "old-token",
		time.Now().Add(inviteTokenTTL))

	if rec := doJSON(t, "POST", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken,
		map[string]any{"email": "friend@example.com"}); rec.Code != http.StatusCreated {
		t.Fatalf("re-invite = %d: %s", rec.Code, rec.Body.String())
	}
	if rec := doJSON(t, "POST", "/api/v1/invites/old-token/accept", friendToken, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("old token after re-invite = %d, want 404", rec.Code)
	}
	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken, nil)
	var pending []map[string]any
	_ = json.Unmarshal(list.Body.Bytes(), &pending)
	if len(pending) != 1 {
		t.Fatalf("pending after re-invite = %d rows, want 1", len(pending))
	}
}

// The owner opening their own invite link: success, no membership row, and
// the token stays live for the actual invitee.
func TestOwnerOpeningOwnInviteIsNoOp(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	trip := createTestTripInLineage(t, owner.ID, "chat-own-invite", "Milos")
	insertInvite(t, owner, "chat-own-invite", "friend@example.com", "own-token",
		time.Now().Add(inviteTokenTTL))

	accept := doJSON(t, "POST", "/api/v1/invites/own-token/accept", ownerToken, nil)
	if accept.Code != http.StatusOK {
		t.Fatalf("owner accept = %d", accept.Code)
	}
	if body := decode(t, accept); body["access"] != "owner" {
		t.Fatalf("owner accept access = %v", body["access"])
	}
	list := doJSON(t, "GET", "/api/v1/trips/"+trip.ID.String()+"/invites", ownerToken, nil)
	var pending []map[string]any
	_ = json.Unmarshal(list.Body.Bytes(), &pending)
	if len(pending) != 1 {
		t.Fatalf("pending after owner self-open = %d rows, want 1 (token stays live)", len(pending))
	}
}
