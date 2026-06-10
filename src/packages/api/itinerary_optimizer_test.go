package main

import "testing"

// place builds an itinerary-location map the way create_itinerary's JSON
// decodes it (numbers as float64).
func place(name string, day float64, timeOfDay string, lat, lng float64) map[string]any {
	return map[string]any{
		"name":        name,
		"day":         day,
		"time_of_day": timeOfDay,
		"latitude":    lat,
		"longitude":   lng,
	}
}

func names(locs []map[string]any) []string {
	out := make([]string, len(locs))
	for i, l := range locs {
		out[i], _ = l["name"].(string)
	}
	return out
}

// Within a single day/time-of-day block, three colinear places handed over in a
// back-and-forth order should be reordered into the shorter monotonic walk.
func TestReorderItineraryByDistanceShortensBlock(t *testing.T) {
	in := []map[string]any{
		place("A", 1, "morning", 0.0, 0.0),
		place("C", 1, "morning", 0.0, 2.0), // far end first => detour
		place("B", 1, "morning", 0.0, 1.0),
	}
	got := names(reorderItineraryByDistance(in))
	want := []string{"A", "B", "C"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("order = %v, want %v", got, want)
		}
	}
}

// Tags must survive the reordering: each place keeps its own day/time_of_day.
func TestReorderItineraryByDistancePreservesTags(t *testing.T) {
	in := []map[string]any{
		place("A", 2, "afternoon", 0.0, 0.0),
		place("B", 2, "afternoon", 0.0, 1.0),
	}
	for _, l := range reorderItineraryByDistance(in) {
		if l["day"].(float64) != 2 || l["time_of_day"].(string) != "afternoon" {
			t.Fatalf("tags lost on %v: %+v", l["name"], l)
		}
	}
}

// Different time-of-day blocks must never interleave, and block order is kept.
func TestReorderItineraryByDistanceKeepsBlocksSeparate(t *testing.T) {
	in := []map[string]any{
		place("m1", 1, "morning", 0.0, 0.0),
		place("e1", 1, "evening", 0.0, 5.0),
		place("m2", 1, "morning", 0.0, 0.1),
		place("e2", 1, "evening", 0.0, 5.1),
	}
	got := names(reorderItineraryByDistance(in))
	// morning block (m1,m2 in some order) comes wholly before the evening block.
	morning := map[string]bool{"m1": true, "m2": true}
	if !morning[got[0]] || !morning[got[1]] || morning[got[2]] || morning[got[3]] {
		t.Fatalf("blocks interleaved or reordered: %v", got)
	}
}

// A block containing a coordinate-less place is left in Claude's order.
func TestReorderItineraryByDistanceSkipsMissingCoords(t *testing.T) {
	noCoords := map[string]any{"name": "X", "day": 1.0, "time_of_day": "morning"}
	in := []map[string]any{
		place("A", 1, "morning", 0.0, 0.0),
		noCoords,
		place("C", 1, "morning", 0.0, 2.0),
	}
	got := names(reorderItineraryByDistance(in))
	want := []string{"A", "X", "C"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("order = %v, want %v (block with missing coords should be untouched)", got, want)
		}
	}
}
