package main

import (
	"net/http"
	"testing"
)

// The "Booked" checkbox on saved bookings: PATCH {booked} round-trips through
// the trip read, toggles back off, and is editor-only.
func TestSavedBookingBookedToggle(t *testing.T) {
	resetDB(t)
	owner, ownerToken := createTestUser(t, "owner@example.com")
	_, viewerToken := createTestUser(t, "viewer@example.com")
	trip := createTestTrip(t, owner.ID, 2)
	id := trip.ID.String()

	rec := doJSON(t, "POST", "/api/v1/trips/"+id+"/accommodations", ownerToken, map[string]any{
		"name": "Casa do Brian", "provider": "airbnb",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add stay = %d: %s", rec.Code, rec.Body.String())
	}
	stay := decode(t, rec)
	if stay["booked"] != false {
		t.Fatalf("new stay should start unbooked: %v", stay)
	}
	stayID := stay["id"].(string)

	rec = doJSON(t, "POST", "/api/v1/trips/"+id+"/segments", ownerToken, map[string]any{
		"mode": "train", "origin": "Lisbon", "destination": "Porto",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("add segment = %d: %s", rec.Code, rec.Body.String())
	}
	segID := decode(t, rec)["id"].(string)

	// Mark both booked; the flag must survive the trip read.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+id+"/accommodations/"+stayID, ownerToken, map[string]any{"booked": true})
	if rec.Code != http.StatusOK {
		t.Fatalf("book stay = %d: %s", rec.Code, rec.Body.String())
	}
	if got := decode(t, rec); got["booked"] != true {
		t.Fatalf("booked stay = %v", got)
	}
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+id+"/segments/"+segID, ownerToken, map[string]any{"booked": true})
	if rec.Code != http.StatusOK {
		t.Fatalf("book segment = %d: %s", rec.Code, rec.Body.String())
	}
	tripView := decode(t, doJSON(t, "GET", "/api/v1/trips/"+id, ownerToken, nil))
	if stays := listOf(t, tripView, "accommodations"); len(stays) != 1 || stays[0]["booked"] != true {
		t.Fatalf("stays after booking = %v", stays)
	}
	if segs := listOf(t, tripView, "segments"); len(segs) != 1 || segs[0]["booked"] != true {
		t.Fatalf("segments after booking = %v", segs)
	}

	// Unchecking works, and a booked-only PATCH must not clobber content.
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+id+"/accommodations/"+stayID, ownerToken, map[string]any{"booked": false})
	if got := decode(t, rec); rec.Code != http.StatusOK || got["booked"] != false || got["name"] != "Casa do Brian" {
		t.Fatalf("unbook stay = %d %v", rec.Code, got)
	}

	// Viewer follows are read-only: the toggle must be rejected.
	shareToken := createShare(t, ownerToken, id, "viewer")
	if rec := joinShare(t, viewerToken, shareToken); rec.Code >= 300 {
		t.Fatalf("join = %d", rec.Code)
	}
	rec = doJSON(t, "PATCH", "/api/v1/trips/"+id+"/segments/"+segID, viewerToken, map[string]any{"booked": true})
	if rec.Code < 400 {
		t.Fatalf("viewer booked toggle should be rejected, got %d", rec.Code)
	}
}
