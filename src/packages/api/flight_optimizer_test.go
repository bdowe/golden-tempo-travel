package main

import "testing"

// leg is a tiny helper to build a single-segment offer with a given schedule.
func offer(id string, price float64, from, to, dep, arr string, dur, stops int) FlightOffer {
	return FlightOffer{
		ID:          id,
		Price:       price,
		Currency:    "USD",
		Stops:       stops,
		DurationMin: dur,
		DepartTime:  dep,
		ArriveTime:  arr,
		Segments:    []FlightLeg{{From: from, To: to, DepartTime: dep, ArriveTime: arr}},
	}
}

// Mirrors the real EWR->PAR Duffel response: four offers sharing one cheap
// nonstop schedule (resold under different carriers), plus two distinct ones.
func TestRankFlightOffersDedupesSharedSchedule(t *testing.T) {
	in := []FlightOffer{
		offer("iberia", 226.81, "EWR", "BVA", "2026-07-15T10:50:00", "2026-07-16T01:09:00", 499, 0),
		offer("ba", 234.23, "EWR", "BVA", "2026-07-15T10:50:00", "2026-07-16T01:09:00", 499, 0),
		offer("aa", 239.74, "EWR", "BVA", "2026-07-15T10:50:00", "2026-07-16T01:09:00", 499, 0),
		offer("duffel", 241.21, "EWR", "BVA", "2026-07-15T10:50:00", "2026-07-16T01:09:00", 499, 0),
		offer("tap", 374.00, "EWR", "ORY", "2026-07-15T17:30:00", "2026-07-16T11:00:00", 690, 1),
		offer("frenchbee", 424.50, "EWR", "ORY", "2026-07-15T23:00:00", "2026-07-16T12:15:00", 435, 0),
	}

	got := RankFlightOffers(in, "balanced")

	if len(got) != 3 {
		t.Fatalf("expected 3 distinct schedules after dedup, got %d", len(got))
	}
	// The shared cheap schedule must be represented exactly once, by Iberia (cheapest).
	count := 0
	for _, o := range got {
		if o.Segments[0].To == "BVA" {
			count++
			if o.ID != "iberia" {
				t.Errorf("expected cheapest BVA offer (iberia) to survive, got %q at $%.2f", o.ID, o.Price)
			}
		}
	}
	if count != 1 {
		t.Errorf("expected the shared BVA schedule to appear once, got %d", count)
	}
}

// twoStop builds a 3-leg EWR->hub1->hub2->FCO itinerary with fixed endpoints,
// varying only the middle (hub1->hub2) leg's timing — mirroring the real Duffel
// case where the same route at the same price appears several times.
func twoStop(id string, price float64, hub1, hub2, midDep, midArr string) FlightOffer {
	return FlightOffer{
		ID: id, Price: price, Currency: "USD", Stops: 2, DurationMin: 1145,
		DepartTime: "2026-07-15T23:10:00", ArriveTime: "2026-07-16T00:15:00",
		Segments: []FlightLeg{
			{From: "EWR", To: hub1, DepartTime: "2026-07-15T23:10:00", ArriveTime: "2026-07-16T10:55:00"},
			{From: hub1, To: hub2, DepartTime: midDep, ArriveTime: midArr},
			{From: hub2, To: "FCO", DepartTime: "2026-07-16T20:15:00", ArriveTime: "2026-07-16T00:15:00"},
		},
	}
}

func TestDedupCollapsesSameRouteDifferentLayoverTiming(t *testing.T) {
	// Same endpoints, same total times, same hubs (OPO, LIS), same price —
	// differ only in the OPO->LIS leg timing. These look identical on the card
	// and must collapse to one.
	in := []FlightOffer{
		twoStop("a", 390, "OPO", "LIS", "2026-07-16T12:35:00", "2026-07-16T13:25:00"),
		twoStop("b", 390, "OPO", "LIS", "2026-07-16T18:00:00", "2026-07-16T19:05:00"),
		twoStop("c", 390, "OPO", "LIS", "2026-07-16T16:00:00", "2026-07-16T17:00:00"),
	}
	got := dedupBySchedule(in, true)
	if len(got) != 1 {
		t.Fatalf("expected same-route/different-layover offers to collapse to 1, got %d", len(got))
	}
}

func TestDedupKeepsDifferentConnectingAirports(t *testing.T) {
	// Same endpoints and overall times but routed through different hubs — these
	// are genuinely different itineraries and must both survive.
	in := []FlightOffer{
		twoStop("via-opo", 390, "OPO", "LIS", "2026-07-16T12:35:00", "2026-07-16T13:25:00"),
		twoStop("via-mad", 390, "MAD", "LIS", "2026-07-16T12:35:00", "2026-07-16T13:25:00"),
	}
	got := dedupBySchedule(in, true)
	if len(got) != 2 {
		t.Fatalf("expected different-hub itineraries to stay separate, got %d", len(got))
	}
}

func TestDedupBySchedulePreservesOrderAndKeepsCheapest(t *testing.T) {
	in := []FlightOffer{
		offer("a-expensive", 500, "JFK", "CDG", "T1", "T2", 480, 0),
		offer("b-other", 300, "JFK", "ORY", "T3", "T4", 500, 1),
		offer("a-cheap", 250, "JFK", "CDG", "T1", "T2", 480, 0),
	}
	got := dedupBySchedule(in, true)
	if len(got) != 2 {
		t.Fatalf("expected 2 schedules, got %d", len(got))
	}
	if got[0].ID != "a-cheap" {
		t.Errorf("expected cheapest of shared schedule (a-cheap) in first slot, got %q", got[0].ID)
	}
	if got[0].Price != 250 {
		t.Errorf("expected price 250, got %v", got[0].Price)
	}
	if got[1].ID != "b-other" {
		t.Errorf("expected b-other preserved in second slot, got %q", got[1].ID)
	}
}

// roundTrip extends offer() with a return slice: retLegs segments (return
// stops = retLegs-1) and a return duration. Top-level fields stay
// outbound-based, mirroring how duffel_service.go builds round-trip offers.
func roundTrip(id string, price float64, from, to, dep, arr string, dur, stops, retDur, retLegs int) FlightOffer {
	o := offer(id, price, from, to, dep, arr, dur, stops)
	o.ReturnDurationMin = retDur
	for i := 0; i < retLegs; i++ {
		o.ReturnSegments = append(o.ReturnSegments, FlightLeg{From: to, To: from})
	}
	return o
}

// Same outbound paired with different return slices must NOT collapse in
// dedup: pre-fix, scheduleSignature hashed only o.Segments, so the cheapest
// pairing swallowed the alternatives that total-duration ranking exists to
// rank (Wave-8 review finding).
func TestDedupKeepsSameOutboundDifferentReturns(t *testing.T) {
	// Identical outbound; A = nonstop 8h return at $600, B = 2-leg 20h return
	// at $550. Price-keyed dedup on an outbound-only signature keeps only B.
	a := roundTrip("fast-return", 600, "JFK", "CDG", "T1", "T2", 420, 0, 480, 1)
	b := roundTrip("slow-return", 550, "JFK", "CDG", "T1", "T2", 420, 0, 1200, 2)

	got := dedupBySchedule([]FlightOffer{a, b}, true)
	if len(got) != 2 {
		t.Fatalf("dedup collapsed distinct return slices: kept %d offers, want 2", len(got))
	}

	ranked := RankFlightOffers([]FlightOffer{a, b}, "time")
	if ranked[0].ID != "fast-return" {
		t.Errorf("time ranking picked %q, want fast-return", ranked[0].ID)
	}
}

// Round-trip "time" ranking must use TOTAL duration (outbound + return), not
// outbound alone: a fast-outbound/slow-return offer with the larger total must
// lose to a slow-outbound/fast-return offer with the smaller total.
func TestRankRoundTripTimeUsesTotalDuration(t *testing.T) {
	in := []FlightOffer{
		// Fast outbound (300) but slow return (600): total 900. Outbound-only
		// ranking would put this first.
		roundTrip("fast-out", 400, "JFK", "CDG", "T1", "T2", 300, 0, 600, 1),
		// Slow outbound (500) but fast return (200): total 700 — the real winner.
		roundTrip("fast-total", 400, "JFK", "CDG", "T3", "T4", 500, 0, 200, 1),
	}
	got := RankFlightOffers(in, "time")
	if got[0].ID != "fast-total" {
		t.Fatalf("time ranking should pick the smaller TOTAL duration (fast-total), got %q first", got[0].ID)
	}
	// Score fields must reflect totals: 700 beats 900.
	if got[0].DurationScore <= got[1].DurationScore {
		t.Errorf("expected fast-total DurationScore (%v) > fast-out (%v)", got[0].DurationScore, got[1].DurationScore)
	}
	// Displayed per-slice fields must be untouched by ranking.
	if got[0].DurationMin != 500 || got[0].ReturnDurationMin != 200 {
		t.Errorf("displayed durations changed: outbound=%d return=%d", got[0].DurationMin, got[0].ReturnDurationMin)
	}
}

// Round-trip stops scoring counts return-slice stops (len(ReturnSegments)-1):
// a nonstop outbound with a 2-stop return (total 2) must lose to a 1-stop
// outbound with a nonstop return (total 1) when durations and price are equal.
func TestRankRoundTripStopsUseTotalStops(t *testing.T) {
	in := []FlightOffer{
		roundTrip("nonstop-out-2stop-back", 400, "JFK", "CDG", "T1", "T2", 480, 0, 480, 3),
		roundTrip("1stop-out-nonstop-back", 400, "JFK", "CDG", "T3", "T4", 480, 1, 480, 1),
	}
	got := RankFlightOffers(in, "balanced")
	if got[0].ID != "1stop-out-nonstop-back" {
		t.Fatalf("balanced ranking should pick the lower TOTAL stops, got %q first", got[0].ID)
	}
	if got[0].StopsScore <= got[1].StopsScore {
		t.Errorf("expected total-stops=1 StopsScore (%v) > total-stops=2 (%v)", got[0].StopsScore, got[1].StopsScore)
	}
	// Displayed outbound stop counts stay per-slice.
	if got[0].Stops != 1 || got[1].Stops != 0 {
		t.Errorf("displayed outbound stops changed: got %d and %d", got[0].Stops, got[1].Stops)
	}
}

// One-way scoring is byte-identical to the pre-round-trip behavior: with no
// return slice, scoringDuration/scoringStops reduce to the outbound fields.
// Pin exact scores on a known one-way fixture so any drift is caught.
func TestRankOneWayScoringUnchanged(t *testing.T) {
	in := []FlightOffer{
		offer("slow-cheap", 200, "JFK", "CDG", "T1", "T2", 600, 1),
		offer("fast-pricey", 400, "JFK", "ORY", "T3", "T4", 400, 0),
	}
	got := RankFlightOffers(in, "time")
	if got[0].ID != "fast-pricey" {
		t.Fatalf("time preset should favor the faster one-way, got %q first", got[0].ID)
	}
	// fast-pricey: price 10->0, duration 10, stops 10 => 0*0.15 + 10*0.60 + 10*0.25 = 8.5
	if got[0].Score != 8.5 {
		t.Errorf("expected fast-pricey score 8.5, got %v", got[0].Score)
	}
	// slow-cheap: price 10, duration 0, stops 0 => 10*0.15 = 1.5
	if got[1].Score != 1.5 {
		t.Errorf("expected slow-cheap score 1.5, got %v", got[1].Score)
	}
}

// Mixed one-way/round-trip lists compare TOTALS as-is: a one-way's total is
// just its outbound, so a round-trip offer with more total flown time scores
// below a one-way with less — no per-slice averaging or trip-type buckets.
func TestRankMixedOneWayAndRoundTripComparesTotals(t *testing.T) {
	in := []FlightOffer{
		// One-way: total 500, 0 stops.
		offer("oneway", 300, "JFK", "CDG", "T1", "T2", 500, 0),
		// Round-trip: outbound 400 (faster than the one-way's outbound!) but
		// total 800 with 1 total stop.
		roundTrip("roundtrip", 300, "JFK", "CDG", "T3", "T4", 400, 0, 400, 2),
	}
	got := RankFlightOffers(in, "time")
	if got[0].ID != "oneway" {
		t.Fatalf("expected the smaller-total one-way to rank first, got %q", got[0].ID)
	}
	if got[0].DurationScore != 10.0 || got[1].DurationScore != 0.0 {
		t.Errorf("expected totals 500 vs 800 to score 10 vs 0, got %v and %v", got[0].DurationScore, got[1].DurationScore)
	}
	if got[0].StopsScore != 10.0 || got[1].StopsScore != 0.0 {
		t.Errorf("expected total stops 0 vs 1 to score 10 vs 0, got %v and %v", got[0].StopsScore, got[1].StopsScore)
	}
}

// cost ranking is unaffected by the round-trip totals change: total_amount
// already prices both slices, so price weighting alone decides equal-price
// factors the same way it did before.
func TestRankRoundTripCostStillPriceDriven(t *testing.T) {
	in := []FlightOffer{
		roundTrip("cheap-slow", 200, "JFK", "CDG", "T1", "T2", 500, 1, 500, 2),
		roundTrip("pricey-fast", 900, "JFK", "CDG", "T3", "T4", 300, 0, 300, 1),
	}
	got := RankFlightOffers(in, "cost")
	if got[0].ID != "cheap-slow" {
		t.Fatalf("cost preset should still favor the cheaper round-trip, got %q first", got[0].ID)
	}
}
