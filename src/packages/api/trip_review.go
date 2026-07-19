package main

import (
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// trip_review.go — a DETERMINISTIC, read-only trip review. It flags real
// problems in a saved trip (unscheduled items, uncovered nights, missing
// transport, over budget, unconfirmed bookings, …) by walking the already-
// loaded exportData. NO AI, NO external calls, NO migration: every finding
// traces to persisted data, so nothing here can hallucinate. reviewTrip is a
// pure function over its inputs — each check is a small, individually-testable
// helper so PR3 can add checkWeather/checkHours alongside without reshaping it.

// Finding is one flagged issue. Day/ItemID follow ItineraryItemResponse's
// nullable-pointer + omitempty convention: absent when the finding isn't tied
// to a specific day or entity. Severity is info|warn|critical; Category is one
// of dates|unscheduled|packing|lodging|transit|budget|bookings.
type Finding struct {
	Severity string  `json:"severity"`
	Category string  `json:"category"`
	Message  string  `json:"message"`
	TripID   string  `json:"trip_id"`
	Day      *int    `json:"day,omitempty"`
	ItemID   *string `json:"item_id,omitempty"`
}

// reviewOptions carries inputs that don't live on exportData. Budget is the
// pre-computed BudgetResponse (nil when there's no budget row) so checkBudget
// stays a pure reader. CheckHours is accepted now but unused in PR1 — PR3
// wires the operating-hours check behind it.
type reviewOptions struct {
	CheckHours bool
	Budget     *BudgetResponse
}

// reviewTrip runs every deterministic check over the loaded trip data and
// returns the findings in a stable order (by day, then severity, then
// category) so the output is reproducible for a given trip snapshot.
func reviewTrip(data exportData, opts reviewOptions) []Finding {
	findings := make([]Finding, 0)
	findings = append(findings, checkDates(data)...)
	findings = append(findings, checkUnscheduled(data)...)
	findings = append(findings, checkDensity(data)...)
	findings = append(findings, checkLodging(data)...)
	findings = append(findings, checkTransit(data)...)
	findings = append(findings, checkBudget(data, opts.Budget)...)
	findings = append(findings, checkBookings(data)...)

	severityRank := map[string]int{"critical": 0, "warn": 1, "info": 2}
	sort.SliceStable(findings, func(i, j int) bool {
		di, dj := findingDayKey(findings[i]), findingDayKey(findings[j])
		if di != dj {
			return di < dj
		}
		if si, sj := severityRank[findings[i].Severity], severityRank[findings[j].Severity]; si != sj {
			return si < sj
		}
		return findings[i].Category < findings[j].Category
	})
	return findings
}

// findingDayKey sorts undated findings (Day == nil) after all day-bound ones.
func findingDayKey(f Finding) int {
	if f.Day == nil {
		return 1 << 30
	}
	return *f.Day
}

// tripDayCount is the number of days the trip's DATES cover (start..end,
// inclusive) — the date-span branch of trip_days.dart's dayCount. Unlike the
// Dart helper it deliberately does NOT fold in tagged item days: this is the
// yardstick the beyond-span check measures items against, so an item tagged
// past the span must not extend the yardstick to hide itself. 0 when undated.
func tripDayCount(trip store.Trip) int {
	if !trip.StartDate.Valid || !trip.EndDate.Valid {
		return 0
	}
	return nightsBetween(trip.StartDate.Time, trip.EndDate.Time) + 1
}

// nightsBetween counts whole calendar days from start to end. pgtype dates are
// UTC midnights, so the subtraction is exact; the +0.5 guards against any FP
// drift.
func nightsBetween(start, end time.Time) int {
	return int(end.Sub(start).Hours()/24 + 0.5)
}

// checkDates flags a trip with no dates (blocks every day-bound check) and any
// item tagged to a day past the trip's span.
func checkDates(d exportData) []Finding {
	tripID := d.Trip.ID.String()
	var out []Finding
	if !d.Trip.StartDate.Valid || !d.Trip.EndDate.Valid {
		out = append(out, Finding{
			Severity: "info", Category: "dates", TripID: tripID,
			Message: "Add trip dates to unlock day-by-day checks.",
		})
		return out // no span → the beyond-span check below is meaningless
	}
	dc := tripDayCount(d.Trip)
	for _, it := range d.Items {
		if it.Day != nil && int(*it.Day) > dc {
			day := int(*it.Day)
			id := it.ID.String()
			out = append(out, Finding{
				Severity: "warn", Category: "dates", TripID: tripID, Day: &day, ItemID: &id,
				Message: fmt.Sprintf("%q is on day %d, past the trip's %d-day span.", it.Name, day, dc),
			})
		}
	}
	return out
}

// checkUnscheduled emits one grouped finding for all items with no day (cleaner
// than one-per-item when many are unscheduled).
func checkUnscheduled(d exportData) []Finding {
	var count int
	for _, it := range d.Items {
		if it.Day == nil {
			count++
		}
	}
	if count == 0 {
		return nil
	}
	msg := "1 item has no day assigned — schedule it to see it on the day plan."
	if count > 1 {
		msg = fmt.Sprintf("%d items have no day assigned — schedule them to see them on the day plan.", count)
	}
	return []Finding{{
		Severity: "info", Category: "unscheduled", TripID: d.Trip.ID.String(), Message: msg,
	}}
}

// checkDensity flags empty days between the first and last scheduled day, and
// over-packed days (more than 6 items, or two+ items sharing a time_of_day).
// Buckets by absolute day so a day split across hubs still counts once.
func checkDensity(d exportData) []Finding {
	tripID := d.Trip.ID.String()
	buckets := map[int][]store.ItineraryItem{}
	minDay, maxDay := 0, 0
	for _, it := range d.Items {
		if it.Day == nil {
			continue
		}
		day := int(*it.Day)
		buckets[day] = append(buckets[day], it)
		if minDay == 0 || day < minDay {
			minDay = day
		}
		if day > maxDay {
			maxDay = day
		}
	}
	if len(buckets) == 0 {
		return nil
	}
	var out []Finding
	for day := minDay; day <= maxDay; day++ {
		if len(buckets[day]) == 0 {
			dd := day
			out = append(out, Finding{
				Severity: "info", Category: "packing", TripID: tripID, Day: &dd,
				Message: fmt.Sprintf("Day %d has nothing planned.", day),
			})
		}
	}
	for day := minDay; day <= maxDay; day++ {
		items := buckets[day]
		if len(items) == 0 {
			continue
		}
		dd := day
		if len(items) > 6 {
			out = append(out, Finding{
				Severity: "warn", Category: "packing", TripID: tripID, Day: &dd,
				Message: fmt.Sprintf("Day %d has %d items planned — that may be too packed.", day, len(items)),
			})
		}
		todCount := map[string]int{}
		for _, it := range items {
			if t := strings.TrimSpace(strPtrVal(it.TimeOfDay)); t != "" {
				todCount[t]++
			}
		}
		// Fixed order keeps the output deterministic.
		for _, tod := range []string{"morning", "afternoon", "evening"} {
			if todCount[tod] > 1 {
				out = append(out, Finding{
					Severity: "warn", Category: "packing", TripID: tripID, Day: &dd,
					Message: fmt.Sprintf("Day %d has %d things scheduled for the %s.", day, todCount[tod], tod),
				})
			}
		}
	}
	return out
}

// checkLodging walks each night of a dated trip (start .. end-1, checkout-
// exclusive) and flags any night no accommodation covers. Gated so an empty
// draft isn't nagged: only runs when the trip is `planned` OR already has at
// least one accommodation.
func checkLodging(d exportData) []Finding {
	if !d.Trip.StartDate.Valid || !d.Trip.EndDate.Valid {
		return nil
	}
	if d.Trip.Status != "planned" && len(d.Accommodations) == 0 {
		return nil
	}
	tripID := d.Trip.ID.String()
	start := d.Trip.StartDate.Time
	nights := nightsBetween(start, d.Trip.EndDate.Time)
	var out []Finding
	for n := 0; n < nights; n++ {
		night := start.AddDate(0, 0, n)
		covered := false
		for _, a := range d.Accommodations {
			if stayCoversNight(a.CheckIn, a.CheckOut, night) {
				covered = true
				break
			}
		}
		if !covered {
			day := n + 1
			out = append(out, Finding{
				Severity: "warn", Category: "lodging", TripID: tripID, Day: &day,
				Message: fmt.Sprintf("No lodging booked for the night of %s.", night.Format("Mon, Jan 2")),
			})
		}
	}
	return out
}

// stayCoversNight is the server twin of trip_days.dart's stayCoversDate:
// check-in <= night < check-out (checkout-exclusive). All values are UTC
// midnights, so the comparison is a plain date compare.
func stayCoversNight(checkIn, checkOut pgtype.Date, night time.Time) bool {
	if !checkIn.Valid || !checkOut.Valid {
		return false
	}
	return !night.Before(checkIn.Time) && night.Before(checkOut.Time)
}

// checkTransit walks consecutive hub groups; when the hub city changes and no
// segment plausibly connects the two, it flags a missing leg. Conservative on
// purpose — a same-city move or a fuzzy origin/destination match suppresses the
// warning to avoid false positives.
func checkTransit(d exportData) []Finding {
	groups := groupExportItems(d.Trip, d.Items)
	if len(groups) < 2 {
		return nil
	}
	tripID := d.Trip.ID.String()
	var out []Finding
	for i := 1; i < len(groups); i++ {
		from, to := groups[i-1].Hub, groups[i].Hub
		if from == "" || to == "" || from == "Itinerary" || to == "Itinerary" {
			continue
		}
		if strings.EqualFold(from, to) {
			continue
		}
		if segmentConnects(d.Segments, from, to) {
			continue
		}
		out = append(out, Finding{
			Severity: "warn", Category: "transit", TripID: tripID,
			Message: fmt.Sprintf("No transport booked from %s to %s.", from, to),
		})
	}
	return out
}

// segmentConnects reports whether any segment plausibly links from→to (either
// direction), via case-insensitive substring matching of the hub cities
// against the segment's origin/destination.
func segmentConnects(segs []store.TripSegment, from, to string) bool {
	from, to = strings.ToLower(from), strings.ToLower(to)
	for _, s := range segs {
		o := strings.ToLower(strings.TrimSpace(strPtrVal(s.Origin)))
		dst := strings.ToLower(strings.TrimSpace(strPtrVal(s.Destination)))
		if fuzzyMatch(o, from) && fuzzyMatch(dst, to) {
			return true
		}
		if fuzzyMatch(o, to) && fuzzyMatch(dst, from) {
			return true
		}
	}
	return false
}

// fuzzyMatch is a lenient, non-empty substring match in either direction.
func fuzzyMatch(a, b string) bool {
	if a == "" || b == "" {
		return false
	}
	return strings.Contains(a, b) || strings.Contains(b, a)
}

// checkBudget flags a trip whose spending exceeds its target.
func checkBudget(d exportData, budget *BudgetResponse) []Finding {
	if budget == nil || budget.Remaining == nil || *budget.Remaining >= 0 {
		return nil
	}
	over := -*budget.Remaining
	return []Finding{{
		Severity: "warn", Category: "budget", TripID: d.Trip.ID.String(),
		Message: fmt.Sprintf("Over budget by %.2f %s.", over, budget.Currency),
	}}
}

// checkBookings flags each unbooked accommodation and segment at info level —
// a gentle "don't forget to confirm", never critical.
func checkBookings(d exportData) []Finding {
	tripID := d.Trip.ID.String()
	var out []Finding
	for _, a := range d.Accommodations {
		if a.Booked {
			continue
		}
		id := a.ID.String()
		out = append(out, Finding{
			Severity: "info", Category: "bookings", TripID: tripID, ItemID: &id,
			Message: fmt.Sprintf("Confirm your booking for %s.", a.Name),
		})
	}
	for _, s := range d.Segments {
		if s.Booked {
			continue
		}
		id := s.ID.String()
		out = append(out, Finding{
			Severity: "info", Category: "bookings", TripID: tripID, ItemID: &id,
			Message: fmt.Sprintf("Confirm your booking for %s.", segmentRoute(s)),
		})
	}
	return out
}
