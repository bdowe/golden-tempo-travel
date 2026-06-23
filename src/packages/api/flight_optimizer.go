package main

import (
	"math"
	"sort"
	"strings"
)

// flightWeights are the per-factor weights for each optimization preset. The
// optimize_for contract follows the same convention as the route optimizer: an
// empty value defaults to "balanced".
type flightWeights struct {
	price    float64
	duration float64
	stops    float64
}

var flightPresets = map[string]flightWeights{
	"cost":     {price: 0.70, duration: 0.20, stops: 0.10},
	"time":     {price: 0.15, duration: 0.60, stops: 0.25},
	"balanced": {price: 0.40, duration: 0.40, stops: 0.20},
}

// normalizeOptimizeFor returns a valid preset name; empty/unknown -> "balanced".
func normalizeOptimizeFor(optimizeFor string) string {
	key := strings.ToLower(strings.TrimSpace(optimizeFor))
	if _, ok := flightPresets[key]; ok {
		return key
	}
	return "balanced"
}

// invScore maps a value into a 0-10 score where the minimum value in the set
// scores 10 and the maximum scores 0 (lower is better for price/duration/stops).
// When all values are equal the factor is neutral (10) so it doesn't penalize.
func invScore(value, min, max float64) float64 {
	if max <= min {
		return 10.0
	}
	return (max - value) / (max - min) * 10.0
}

// scheduleSignature identifies an offer at the level a traveler perceives it on
// a summary card: origin, final destination, overall departure/arrival times,
// and the ordered list of connecting airports. Offers that share a signature
// look identical in the list, so we treat them as one option and keep only the
// cheapest. This intentionally ignores the *timing* of intermediate legs: two
// itineraries on the same route through the same hubs that differ only in, say,
// a 5h vs 7h layout in a connecting city (with the same total duration) are
// indistinguishable on the card and otherwise appear as confusing duplicates.
// Routes through different hubs keep different signatures and stay separate.
func scheduleSignature(o FlightOffer) string {
	if len(o.Segments) == 0 {
		return ""
	}
	first := o.Segments[0]
	last := o.Segments[len(o.Segments)-1]
	parts := []string{first.From, last.To, first.DepartTime, last.ArriveTime}
	for i := 0; i < len(o.Segments)-1; i++ {
		parts = append(parts, o.Segments[i].To) // connecting airport
	}
	return strings.Join(parts, "|")
}

// dedupBySchedule collapses offers that share an identical schedule, keeping the
// lowest-priced offer for each. Order of first appearance is preserved so the
// result is stable before ranking. Offers without segments fall back to a
// signature of their top-level depart/arrive times so they are never dropped.
func dedupBySchedule(offers []FlightOffer) []FlightOffer {
	best := make(map[string]int, len(offers)) // signature -> index in result
	result := make([]FlightOffer, 0, len(offers))
	for _, o := range offers {
		sig := scheduleSignature(o)
		if sig == "" {
			sig = o.DepartTime + "-" + o.ArriveTime
		}
		if idx, ok := best[sig]; ok {
			if o.Price < result[idx].Price {
				result[idx] = o
			}
			continue
		}
		best[sig] = len(result)
		result = append(result, o)
	}
	return result
}

// RankFlightOffers collapses duplicate schedules (keeping the cheapest of each),
// then scores each remaining offer on price, duration, and stops (each
// normalized to 0-10 across the result set, lower being better), combines them
// using the preset weights, and returns the offers sorted by descending score.
// The *_score and Score fields on each offer are populated in place.
func RankFlightOffers(offers []FlightOffer, optimizeFor string) []FlightOffer {
	if len(offers) == 0 {
		return offers
	}

	offers = dedupBySchedule(offers)

	w := flightPresets[normalizeOptimizeFor(optimizeFor)]

	minPrice, maxPrice := math.Inf(1), math.Inf(-1)
	minDur, maxDur := math.Inf(1), math.Inf(-1)
	minStops, maxStops := math.Inf(1), math.Inf(-1)
	for _, o := range offers {
		minPrice, maxPrice = math.Min(minPrice, o.Price), math.Max(maxPrice, o.Price)
		minDur, maxDur = math.Min(minDur, float64(o.DurationMin)), math.Max(maxDur, float64(o.DurationMin))
		minStops, maxStops = math.Min(minStops, float64(o.Stops)), math.Max(maxStops, float64(o.Stops))
	}

	for i := range offers {
		o := &offers[i]
		o.PriceScore = round2(invScore(o.Price, minPrice, maxPrice))
		o.DurationScore = round2(invScore(float64(o.DurationMin), minDur, maxDur))
		o.StopsScore = round2(invScore(float64(o.Stops), minStops, maxStops))
		o.Score = round2(o.PriceScore*w.price + o.DurationScore*w.duration + o.StopsScore*w.stops)
	}

	sort.SliceStable(offers, func(i, j int) bool {
		return offers[i].Score > offers[j].Score
	})
	return offers
}

func round2(f float64) float64 {
	return math.Round(f*100) / 100
}
