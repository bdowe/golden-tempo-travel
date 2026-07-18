package main

import (
	"net/http"
	"testing"
)

// Helpers to pull the stays/segments arrays out of a decoded response and
// index them by auto_key / name for loose assertions.
func listOf(t *testing.T, body map[string]any, field string) []map[string]any {
	t.Helper()
	raw, _ := body[field].([]any)
	out := make([]map[string]any, 0, len(raw))
	for _, e := range raw {
		m, ok := e.(map[string]any)
		if !ok {
			t.Fatalf("%s entry not an object: %v", field, e)
		}
		out = append(out, m)
	}
	return out
}

func findByKey(rows []map[string]any, autoKey string) map[string]any {
	for _, r := range rows {
		if r["auto_key"] == autoKey {
			return r
		}
	}
	return nil
}

func syncDrafts(t *testing.T, token, tripID string, stays, transports []map[string]any) map[string]any {
	t.Helper()
	rec := doJSON(t, "PUT", "/api/v1/trips/"+tripID+"/booking-drafts", token, map[string]any{
		"stays": stays, "transports": transports,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("sync booking drafts = %d: %s", rec.Code, rec.Body.String())
	}
	return decode(t, rec)
}

func lisbonStay() map[string]any {
	return map[string]any{
		"auto_key": "stay:lisbon", "name": "Stay in Lisbon", "address": "Lisbon",
		"check_in": "2026-09-01", "check_out": "2026-09-04",
	}
}

func lisbonPortoLeg() map[string]any {
	return map[string]any{
		"auto_key": "transport:lisbon>>porto", "mode": "flight",
		"origin": "Lisbon", "destination": "Porto", "depart_date": "2026-09-04",
	}
}

// The full draft lifecycle: seed -> re-sync updates in place -> confirm via
// PATCH -> confirmed rows survive divergent and key-omitting syncs -> stale
// drafts prune.
func TestBookingDraftLifecycle(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	id := trip.ID.String()

	// Seed one stay + one leg.
	body := syncDrafts(t, token, id, []map[string]any{lisbonStay()}, []map[string]any{lisbonPortoLeg()})
	stays := listOf(t, body, "accommodations")
	if len(stays) != 1 || stays[0]["auto"] != true || stays[0]["auto_key"] != "stay:lisbon" {
		t.Fatalf("seeded stays = %v", stays)
	}
	segs := listOf(t, body, "segments")
	if len(segs) != 1 || segs[0]["auto"] != true || segs[0]["mode"] != "flight" {
		t.Fatalf("seeded segments = %v", segs)
	}

	// Re-sync with shifted dates updates the draft in place (same row count).
	stay := lisbonStay()
	stay["check_in"] = "2026-09-02"
	body = syncDrafts(t, token, id, []map[string]any{stay}, []map[string]any{lisbonPortoLeg()})
	stays = listOf(t, body, "accommodations")
	if len(stays) != 1 || stays[0]["check_in"] != "2026-09-02" {
		t.Fatalf("re-synced stays = %v", stays)
	}

	// Confirm the stay with an edit; the segment with an empty "Keep" PATCH.
	stayID := stays[0]["id"].(string)
	rec := doJSON(t, "PATCH", "/api/v1/trips/"+id+"/accommodations/"+stayID, token, map[string]any{
		"name": "Casa do Brian", "provider": "airbnb",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("confirm stay = %d: %s", rec.Code, rec.Body.String())
	}
	if got := decode(t, rec); got["auto"] != false || got["name"] != "Casa do Brian" {
		t.Fatalf("confirmed stay = %v", got)
	}
	segID := listOf(t, body, "segments")[0]["id"].(string)
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+id+"/segments/"+segID, token, map[string]any{})
	if rec.Code != http.StatusOK {
		t.Fatalf("keep segment = %d: %s", rec.Code, rec.Body.String())
	}
	if got := decode(t, rec); got["auto"] != false {
		t.Fatalf("kept segment = %v", got)
	}

	// A divergent sync must not touch confirmed rows...
	stay["check_in"] = "2026-09-03"
	body = syncDrafts(t, token, id, []map[string]any{stay}, []map[string]any{lisbonPortoLeg()})
	stays = listOf(t, body, "accommodations")
	if len(stays) != 1 || stays[0]["name"] != "Casa do Brian" || stays[0]["check_in"] != "2026-09-02" {
		t.Fatalf("confirmed stay after divergent sync = %v", stays)
	}
	// ...and a sync omitting their keys must not prune them.
	body = syncDrafts(t, token, id, nil, nil)
	if len(listOf(t, body, "accommodations")) != 1 || len(listOf(t, body, "segments")) != 1 {
		t.Fatalf("confirmed rows pruned by empty sync: %v", body)
	}

	// A fresh draft with a new key prunes when its leg disappears.
	porto := map[string]any{"auto_key": "stay:porto", "name": "Stay in Porto"}
	body = syncDrafts(t, token, id, []map[string]any{porto}, nil)
	if findByKey(listOf(t, body, "accommodations"), "stay:porto") == nil {
		t.Fatalf("porto draft missing: %v", body)
	}
	body = syncDrafts(t, token, id, nil, nil)
	if findByKey(listOf(t, body, "accommodations"), "stay:porto") != nil {
		t.Fatalf("stale porto draft survived prune: %v", body)
	}
}

// Deleting a draft tombstones it: gone from every read, and the same sync key
// cannot resurrect it. Deleting a confirmed row still hard-deletes.
func TestBookingDraftDismissal(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	id := trip.ID.String()

	body := syncDrafts(t, token, id, []map[string]any{lisbonStay()}, []map[string]any{lisbonPortoLeg()})
	stayID := listOf(t, body, "accommodations")[0]["id"].(string)

	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+id+"/accommodations/"+stayID, token, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("dismiss draft = %d", rec.Code)
	}
	tripView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+id, token, nil))
	if len(listOf(t, tripView, "accommodations")) != 0 {
		t.Fatalf("dismissed draft still listed: %v", tripView["accommodations"])
	}
	// Same key re-synced: the tombstone holds.
	body = syncDrafts(t, token, id, []map[string]any{lisbonStay()}, []map[string]any{lisbonPortoLeg()})
	if len(listOf(t, body, "accommodations")) != 0 {
		t.Fatalf("dismissed draft resurrected: %v", body["accommodations"])
	}
	// Once the leg disappears the tombstone prunes; the key can re-seed later.
	body = syncDrafts(t, token, id, nil, []map[string]any{lisbonPortoLeg()})
	body = syncDrafts(t, token, id, []map[string]any{lisbonStay()}, []map[string]any{lisbonPortoLeg()})
	if len(listOf(t, body, "accommodations")) != 1 {
		t.Fatalf("re-seed after prune failed: %v", body["accommodations"])
	}

	// Confirm the re-seeded draft, then delete: hard delete, not a tombstone —
	// the next sync with the same key seeds a fresh draft.
	stayID = listOf(t, body, "accommodations")[0]["id"].(string)
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+id+"/accommodations/"+stayID, token, map[string]any{}); rec.Code != http.StatusOK {
		t.Fatalf("confirm = %d", rec.Code)
	}
	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+id+"/accommodations/"+stayID, token, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("delete confirmed = %d", rec.Code)
	}
	body = syncDrafts(t, token, id, []map[string]any{lisbonStay()}, []map[string]any{lisbonPortoLeg()})
	if len(listOf(t, body, "accommodations")) != 1 {
		t.Fatalf("hard-deleted row blocked re-seed: %v", body["accommodations"])
	}
}

// Drafts are editor-facing working state: viewer follows, the public share
// view, and duplicates all see confirmed rows only.
func TestBookingDraftVisibility(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, viewerToken := createTestUser(t, "viewer@example.com")
	_, copierToken := createTestUser(t, "copier@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	id := trip.ID.String()

	body := syncDrafts(t, ownerToken, id, []map[string]any{lisbonStay()}, []map[string]any{lisbonPortoLeg()})
	// Confirm the segment so each surface has one confirmed row to show.
	segID := listOf(t, body, "segments")[0]["id"].(string)
	if rec := doJSON(t, "PATCH", "/api/v1/trips/"+id+"/segments/"+segID, ownerToken, map[string]any{}); rec.Code != http.StatusOK {
		t.Fatalf("confirm segment = %d", rec.Code)
	}

	shareToken := createShare(t, ownerToken, id, "viewer")
	if rec := joinShare(t, viewerToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	// Owner sees the draft stay + confirmed segment.
	ownerView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+id, ownerToken, nil))
	if len(listOf(t, ownerView, "accommodations")) != 1 || len(listOf(t, ownerView, "segments")) != 1 {
		t.Fatalf("owner view = %v", ownerView)
	}

	// Viewer follow: no draft stay, confirmed segment only.
	viewerView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+id, viewerToken, nil))
	if len(listOf(t, viewerView, "accommodations")) != 0 {
		t.Fatalf("viewer sees drafts: %v", viewerView["accommodations"])
	}
	if len(listOf(t, viewerView, "segments")) != 1 {
		t.Fatalf("viewer missing confirmed segment: %v", viewerView["segments"])
	}

	// Public share view: same boundary.
	shared := decode(t, doJSON(t, "GET", "/api/v1/shared/"+shareToken, "", nil))
	sharedTrip, _ := shared["trip"].(map[string]any)
	if sharedTrip == nil {
		t.Fatalf("shared response missing trip: %v", shared)
	}
	if len(listOf(t, sharedTrip, "accommodations")) != 0 {
		t.Fatalf("public share sees drafts: %v", sharedTrip["accommodations"])
	}
	if len(listOf(t, sharedTrip, "segments")) != 1 {
		t.Fatalf("public share missing confirmed segment: %v", sharedTrip["segments"])
	}

	// Duplicate: copies the confirmed segment, never the draft (which would
	// otherwise arrive as a confirmed booking).
	rec := doJSON(t, "POST", "/api/v1/shared/"+shareToken+"/duplicate", copierToken, nil)
	if rec.Code != http.StatusCreated && rec.Code != http.StatusOK {
		t.Fatalf("duplicate = %d: %s", rec.Code, rec.Body.String())
	}
	copyID, _ := decode(t, rec)["id"].(string)
	if copyID == "" {
		t.Fatalf("duplicate response missing id")
	}
	copyView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+copyID, copierToken, nil))
	if len(listOf(t, copyView, "accommodations")) != 0 {
		t.Fatalf("duplicate copied drafts: %v", copyView["accommodations"])
	}
	segs := listOf(t, copyView, "segments")
	if len(segs) != 1 || segs[0]["auto"] != false {
		t.Fatalf("duplicate segments = %v", segs)
	}
}

// Like the booking-todos sync, the drafts sync runs on every trip load and
// must never stamp updated_by attribution; dismissing a suggestion is
// likewise passive.
func TestBookingDraftSyncIsPassive(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, editorToken := createTestUser(t, "editor@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	id := trip.ID.String()
	shareToken := createShare(t, ownerToken, id, "editor")
	if rec := joinShare(t, editorToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}

	body := syncDrafts(t, editorToken, id, []map[string]any{lisbonStay()}, nil)
	stayID := listOf(t, body, "accommodations")[0]["id"].(string)
	if rec := doJSON(t, "DELETE", "/api/v1/trips/"+id+"/accommodations/"+stayID, editorToken, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("dismiss = %d", rec.Code)
	}

	ownerView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+id, ownerToken, nil))
	if ownerView["updated_by_name"] != nil {
		t.Fatalf("passive drafts sync/dismiss stamped attribution: %v", ownerView["updated_by_name"])
	}
}
