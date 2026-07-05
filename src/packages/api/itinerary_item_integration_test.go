package main

import (
	"context"
	"net/http"
	"testing"

	"travel-route-planner/store"
)

func TestItemOwnerCRUDAndReorder(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 3)
	base := "/api/v1/trips/" + trip.ID.String()

	add := doJSON(t, "POST", base+"/items", token, map[string]any{
		"name": "New Stop", "latitude": 37.99, "longitude": 23.74, "category": "restaurant",
	})
	if add.Code != http.StatusCreated && add.Code != http.StatusOK {
		t.Fatalf("add = %d: %s", add.Code, add.Body.String())
	}
	// The add response is the whole updated trip; find the new item's id in
	// the store by its name.
	var newID string
	created, err := store.New(dbPool).GetItineraryItemsByTrip(context.Background(), trip.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range created {
		if it.Name == "New Stop" {
			newID = it.ID.String()
		}
	}
	if newID == "" {
		t.Fatalf("added item not found in store; add response: %s", add.Body.String())
	}

	patch := doJSON(t, "PATCH", base+"/items/"+newID, token, map[string]any{"name": "Renamed Stop"})
	if patch.Code != http.StatusOK {
		t.Fatalf("patch = %d: %s", patch.Code, patch.Body.String())
	}

	// Reorder: reverse the full item list.
	items, err := store.New(dbPool).GetItineraryItemsByTrip(context.Background(), trip.ID)
	if err != nil {
		t.Fatal(err)
	}
	ids := make([]string, 0, len(items))
	for i := len(items) - 1; i >= 0; i-- {
		ids = append(ids, items[i].ID.String())
	}
	reorder := doJSON(t, "PUT", base+"/items/order", token, map[string]any{"item_ids": ids})
	if reorder.Code != http.StatusOK && reorder.Code != http.StatusNoContent {
		t.Fatalf("reorder = %d: %s", reorder.Code, reorder.Body.String())
	}
	after, err := store.New(dbPool).GetItineraryItemsByTrip(context.Background(), trip.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after[0].ID.String() != ids[0] {
		t.Fatalf("reorder not applied: first item %s, want %s", after[0].ID, ids[0])
	}

	del := doJSON(t, "DELETE", base+"/items/"+newID, token, nil)
	if del.Code != http.StatusNoContent && del.Code != http.StatusOK {
		t.Fatalf("delete = %d", del.Code)
	}
}

func TestItemCrossUserIsolation(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, intruderToken := createTestUser(t, "intruder@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	base := "/api/v1/trips/" + trip.ID.String()

	items, err := store.New(dbPool).GetItineraryItemsByTrip(context.Background(), trip.ID)
	if err != nil {
		t.Fatal(err)
	}
	itemID := items[0].ID.String()

	cases := []struct {
		method, path string
		body         any
	}{
		{"POST", base + "/items", map[string]any{"name": "X", "latitude": 1.0, "longitude": 1.0}},
		{"PATCH", base + "/items/" + itemID, map[string]any{"name": "Hijack"}},
		{"DELETE", base + "/items/" + itemID, nil},
		{"PUT", base + "/items/order", map[string]any{"item_ids": []string{itemID}}},
	}
	for _, tc := range cases {
		if rec := doJSON(t, tc.method, tc.path, intruderToken, tc.body); rec.Code != http.StatusNotFound {
			t.Fatalf("intruder %s %s = %d, want 404", tc.method, tc.path, rec.Code)
		}
	}

	// Sanity: the owner still can.
	if rec := doJSON(t, "PATCH", base+"/items/"+itemID, ownerToken, map[string]any{"name": "Mine"}); rec.Code != http.StatusOK {
		t.Fatalf("owner patch after intrusion attempts = %d", rec.Code)
	}
}

func TestItemValidation(t *testing.T) {
	resetDB(t)
	owner, token := createTestUser(t, "owner@example.com")
	trip := createTestTrip(t, owner.ID, 1)
	base := "/api/v1/trips/" + trip.ID.String()

	if rec := doJSON(t, "POST", base+"/items", token, map[string]any{
		"name": "Bad Cat", "latitude": 1.0, "longitude": 1.0, "category": "spaceport",
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid category = %d, want 400", rec.Code)
	}
	if rec := doJSON(t, "POST", base+"/items", token, map[string]any{
		"name": "Bad Time", "latitude": 1.0, "longitude": 1.0, "time_of_day": "brunch",
	}); rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid time_of_day = %d, want 400", rec.Code)
	}

	// A stale/partial reorder list conflicts.
	rec := doJSON(t, "PUT", base+"/items/order", token, map[string]any{"item_ids": []string{}})
	if rec.Code != http.StatusConflict {
		t.Fatalf("stale reorder = %d, want 409", rec.Code)
	}
}
