package main

import (
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// item builds a stored itinerary row the way GetItineraryItemsByTrip returns
// it. day 0 means unscheduled (nil); city/dayTripFrom "" mean unset.
func item(name string, day int, city, dayTripFrom string) store.ItineraryItem {
	it := store.ItineraryItem{Name: name, Latitude: 1, Longitude: 1}
	if day > 0 {
		d := int32(day)
		it.Day = &d
	}
	if city != "" {
		it.City = &city
	}
	if dayTripFrom != "" {
		it.DayTripFrom = &dayTripFrom
	}
	return it
}

func intPtr(v int) *int { return &v }

func itemNames(locs []map[string]any) []string {
	out := make([]string, len(locs))
	for i, l := range locs {
		out[i], _ = l["name"].(string)
	}
	return out
}

func assertOrder(t *testing.T, got []map[string]any, want []string) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("order = %v, want %v", itemNames(got), want)
	}
	for i, n := range itemNames(got) {
		if n != want[i] {
			t.Fatalf("order = %v, want %v", itemNames(got), want)
		}
	}
}

// --- hubOfItem ---

func TestHubOfItemPrefersDayTripHub(t *testing.T) {
	if h := hubOfItem(item("Versailles", 2, "Versailles", "Paris")); h != "Paris" {
		t.Fatalf("hub = %q, want Paris", h)
	}
	if h := hubOfItem(item("Louvre", 1, "Paris", "")); h != "Paris" {
		t.Fatalf("hub = %q, want Paris", h)
	}
	if h := hubOfItem(item("Mystery", 0, "", "")); h != "" {
		t.Fatalf("hub = %q, want empty", h)
	}
}

func TestHubOfItemTrimsWhitespace(t *testing.T) {
	if h := hubOfItem(item("x", 1, " Lisbon ", "")); h != "Lisbon" {
		t.Fatalf("hub = %q, want Lisbon", h)
	}
}

// --- insertPositionForDay ---

func TestInsertPositionForDay(t *testing.T) {
	items := []store.ItineraryItem{
		item("a", 1, "Paris", ""),
		item("b", 1, "Paris", ""),
		item("c", 2, "Paris", ""),
		item("u", 0, "", ""), // unscheduled tail
	}
	cases := []struct {
		name string
		day  *int
		want int
	}{
		{"nil day appends", nil, 4},
		{"end of day 1", intPtr(1), 2},
		{"end of day 2 before unscheduled", intPtr(2), 3},
		{"day past end lands after last dated item", intPtr(9), 3},
	}
	for _, c := range cases {
		if got := insertPositionForDay(items, c.day); got != c.want {
			t.Fatalf("%s: pos = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestInsertPositionForDayEmptyTrip(t *testing.T) {
	if got := insertPositionForDay(nil, intPtr(1)); got != 0 {
		t.Fatalf("pos = %d, want 0", got)
	}
	if got := insertPositionForDay(nil, nil); got != 0 {
		t.Fatalf("pos = %d, want 0", got)
	}
}

// --- spliceSection ---

func parisRome() []store.ItineraryItem {
	return []store.ItineraryItem{
		item("Louvre", 1, "Paris", ""),
		item("Orsay", 1, "Paris", ""),
		item("Versailles", 2, "Versailles", "Paris"),
		item("Colosseum", 3, "Rome", ""),
		item("Forum", 3, "Rome", ""),
	}
}

func TestSpliceSectionDayKeepsOtherDays(t *testing.T) {
	repl := []map[string]any{{"name": "Pompidou", "latitude": 1.0, "longitude": 1.0}}
	got, err := spliceSection(parisRome(), sectionSelector{Scope: "day", Day: intPtr(1)}, repl)
	if err != nil {
		t.Fatal(err)
	}
	assertOrder(t, got, []string{"Pompidou", "Versailles", "Colosseum", "Forum"})
}

func TestSpliceSectionCityFoldsDayTrips(t *testing.T) {
	// City scope on the hub removes its day trips too (Versailles → Paris hub).
	repl := []map[string]any{{"name": "Montmartre", "latitude": 1.0, "longitude": 1.0}}
	got, err := spliceSection(parisRome(), sectionSelector{Scope: "city", City: "paris"}, repl)
	if err != nil {
		t.Fatal(err)
	}
	assertOrder(t, got, []string{"Montmartre", "Colosseum", "Forum"})
}

func TestSpliceSectionDayWithCityDisambiguator(t *testing.T) {
	// Legacy trips can repeat day numbers across cities: two "day 1" blocks.
	items := []store.ItineraryItem{
		item("Louvre", 1, "Paris", ""),
		item("Colosseum", 1, "Rome", ""),
	}
	repl := []map[string]any{{"name": "Pantheon", "latitude": 1.0, "longitude": 1.0}}
	got, err := spliceSection(items, sectionSelector{Scope: "day", Day: intPtr(1), City: "Rome"}, repl)
	if err != nil {
		t.Fatal(err)
	}
	assertOrder(t, got, []string{"Louvre", "Pantheon"})
}

func TestSpliceSectionTripReplacesEverything(t *testing.T) {
	repl := []map[string]any{{"name": "Only", "latitude": 1.0, "longitude": 1.0}}
	got, err := spliceSection(parisRome(), sectionSelector{Scope: "trip"}, repl)
	if err != nil {
		t.Fatal(err)
	}
	assertOrder(t, got, []string{"Only"})
}

func TestSpliceSectionMissErrorsWithValidOptions(t *testing.T) {
	_, err := spliceSection(parisRome(), sectionSelector{Scope: "day", Day: intPtr(9)}, nil)
	if err == nil {
		t.Fatal("expected error for unmatched day")
	}
	for _, want := range []string{"day 9", "Paris", "Rome"} {
		if !strings.Contains(err.Error(), want) {
			t.Fatalf("error %q should mention %q", err, want)
		}
	}
	if _, err := spliceSection(parisRome(), sectionSelector{Scope: "city", City: "Lisbon"}, nil); err == nil {
		t.Fatal("expected error for unmatched city")
	}
}

func TestSpliceSectionValidatesSelector(t *testing.T) {
	if _, err := spliceSection(parisRome(), sectionSelector{Scope: "day"}, nil); err == nil {
		t.Fatal("scope day without day number should error")
	}
	if _, err := spliceSection(parisRome(), sectionSelector{Scope: "city"}, nil); err == nil {
		t.Fatal("scope city without city should error")
	}
	if _, err := spliceSection(parisRome(), sectionSelector{Scope: "week"}, nil); err == nil {
		t.Fatal("unknown scope should error")
	}
}

func TestSpliceSectionKeptItemsPreserveTags(t *testing.T) {
	cat, tod := "attraction", "morning"
	items := parisRome()
	items[3].Category = &cat
	items[3].TimeOfDay = &tod
	got, err := spliceSection(items, sectionSelector{Scope: "day", Day: intPtr(1)},
		[]map[string]any{{"name": "Pompidou", "latitude": 1.0, "longitude": 1.0}})
	if err != nil {
		t.Fatal(err)
	}
	var colosseum map[string]any
	for _, l := range got {
		if l["name"] == "Colosseum" {
			colosseum = l
		}
	}
	if colosseum == nil {
		t.Fatal("Colosseum missing from spliced result")
	}
	if colosseum["category"] != "attraction" || colosseum["time_of_day"] != "morning" ||
		colosseum["city"] != "Rome" || colosseum["day"] != float64(3) {
		t.Fatalf("kept item lost tags: %+v", colosseum)
	}
}

// Round-trip: locationFromItem output must coerce back losslessly.
func TestLocationFromItemRoundTrip(t *testing.T) {
	src := item("Versailles", 2, "Versailles", "Paris")
	pid, addr := "pid-1", "Place d'Armes"
	src.PlaceID = &pid
	src.Address = &addr
	params := itemParamsFromLocation(src.TripID, 0, locationFromItem(src))
	if params.Name != "Versailles" || params.PlaceID == nil || *params.PlaceID != "pid-1" ||
		params.Address == nil || *params.Address != addr ||
		params.City == nil || *params.City != "Versailles" ||
		params.DayTripFrom == nil || *params.DayTripFrom != "Paris" ||
		params.Day == nil || *params.Day != 2 {
		t.Fatalf("round trip lost fields: %+v", params)
	}
}

// Attribution snapshots must survive a section rewrite: locationFromItem
// carries them and itemParamsFromLocation coerces them back (specs/add-to-itinerary).
func TestLocationFromItemRoundTripsAttribution(t *testing.T) {
	src := item("Tasca da Ana", 1, "Lisbon", "")
	name := "Ana"
	src.LocalSourceName = &name
	recID := uuid.MustParse("6ba7b810-9dad-11d1-80b4-00c04fd430c8")
	src.LocalRecommendationID = pgtype.UUID{Bytes: recID, Valid: true}

	params := itemParamsFromLocation(src.TripID, 0, locationFromItem(src))
	if params.LocalSourceName == nil || *params.LocalSourceName != "Ana" {
		t.Fatalf("local_source_name lost: %+v", params.LocalSourceName)
	}
	if !params.LocalRecommendationID.Valid || params.LocalRecommendationID.Bytes != recID {
		t.Fatalf("local_recommendation_id lost: %+v", params.LocalRecommendationID)
	}

	// Unattributed items stay unattributed (no empty-string snapshots).
	plain := itemParamsFromLocation(src.TripID, 0, locationFromItem(item("Louvre", 1, "Paris", "")))
	if plain.LocalSourceName != nil || plain.LocalRecommendationID.Valid {
		t.Fatalf("plain item grew attribution: %+v %+v", plain.LocalSourceName, plain.LocalRecommendationID)
	}
}
