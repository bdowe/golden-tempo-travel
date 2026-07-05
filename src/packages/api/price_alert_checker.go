package main

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// Price-alert checker (specs/price-alerts): an in-process ticker that
// re-searches watched routes via Duffel and emails owners on a real drop.
// Single-process by design — if the API ever runs multi-instance, add
// FOR UPDATE SKIP LOCKED to ListDuePriceAlerts.

const (
	// minDropFraction/minDropAbs absorb Duffel offer-to-offer noise in
	// any-drop mode: a "drop" must be at least 5% AND $5 below the baseline.
	minDropFraction = 0.05
	minDropAbs      = 5.0
	// notifyEpsilon: a further drop must beat the last notified price by at
	// least this much to re-notify (target mode).
	notifyEpsilon = 1.0

	defaultAlertTickMinutes = 5
	defaultAlertCheckHours  = 6
	alertBatchSize          = 25
	alertPerCallGap         = time.Second
)

type alertChecker struct {
	duffel     *DuffelService
	interval   time.Duration // ticker period
	checkEvery time.Duration // per-alert freshness window
	batchSize  int
	perCallGap time.Duration
}

// startAlertChecker launches the background loop. No-ops (with a log line)
// when persistence or the flight provider is unavailable; alert CRUD still
// works and checking resumes on next boot once configured.
func startAlertChecker(ctx context.Context) {
	if dbPool == nil {
		log.Printf("price alerts: checker disabled (no database)")
		return
	}
	if duffelService.Token == "" {
		log.Printf("price alerts: checker disabled (DUFFEL_ACCESS_TOKEN not set)")
		return
	}
	c := &alertChecker{
		duffel:     duffelService,
		interval:   time.Duration(envInt("ALERT_TICK_MINUTES", defaultAlertTickMinutes)) * time.Minute,
		checkEvery: time.Duration(envInt("ALERT_CHECK_HOURS", defaultAlertCheckHours)) * time.Hour,
		batchSize:  alertBatchSize,
		perCallGap: alertPerCallGap,
	}
	go c.run(ctx)
	log.Printf("price alerts: checker started (tick %s, per-alert freshness %s)", c.interval, c.checkEvery)
}

func envInt(name string, fallback int) int {
	if v, err := strconv.Atoi(os.Getenv(name)); err == nil && v > 0 {
		return v
	}
	return fallback
}

func (c *alertChecker) run(ctx context.Context) {
	// Jitter the first tick so restarts don't synchronize a burst of Duffel
	// searches.
	select {
	case <-ctx.Done():
		return
	case <-time.After(time.Duration(rand.Int63n(int64(c.interval)))):
	}
	ticker := time.NewTicker(c.interval)
	defer ticker.Stop()
	for {
		c.runOnce(ctx)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// runOnce performs one checking cycle. Exported-in-spirit: the testable unit.
func (c *alertChecker) runOnce(ctx context.Context) {
	q := store.New(dbPool)

	if n, err := q.ExpirePastPriceAlerts(ctx); err != nil {
		log.Printf("price alerts: expire pass failed: %v", err)
	} else if n > 0 {
		log.Printf("price alerts: expired %d past alerts", n)
	}

	cutoff := time.Now().Add(-c.checkEvery)
	due, err := q.ListDuePriceAlerts(ctx, store.ListDuePriceAlertsParams{
		LastCheckedAt: pgTimestamptz(cutoff),
		Limit:         int32(c.batchSize),
	})
	if err != nil {
		log.Printf("price alerts: could not list due alerts: %v", err)
		return
	}
	if len(due) == 0 {
		return
	}

	// One Duffel search per distinct watched route per cycle, however many
	// users watch it.
	groups := map[string][]store.ListDuePriceAlertsRow{}
	var order []string
	for _, row := range due {
		key := alertSearchKey(row.PriceAlert)
		if _, seen := groups[key]; !seen {
			order = append(order, key)
		}
		groups[key] = append(groups[key], row)
	}

	for i, key := range order {
		if ctx.Err() != nil {
			return
		}
		if i > 0 {
			time.Sleep(c.perCallGap)
		}
		rows := groups[key]
		a := rows[0].PriceAlert
		offers, err := c.duffel.SearchFlightOffers(ctx, FlightSearchRequest{
			Origin: a.Origin, Destination: a.Destination,
			DepartDate: dateString(a.DepartDate), ReturnDate: dateString(a.ReturnDate),
			Adults: int(a.Adults), CabinClass: a.CabinClass,
		})
		if err != nil {
			// Touch (timestamp only) so a permanently-failing route rotates
			// to the back of the due queue instead of retrying every tick
			// and starving the batch.
			log.Printf("price alerts: search %s failed: %v", key, err)
			c.touch(ctx, q, rows)
			continue
		}
		lowest, ok := lowestOffer(offers)
		if !ok {
			log.Printf("price alerts: search %s returned no offers", key)
			c.touch(ctx, q, rows)
			continue
		}
		for _, row := range rows {
			c.settle(ctx, q, row, lowest)
		}
	}
}

func (c *alertChecker) touch(ctx context.Context, q *store.Queries, rows []store.ListDuePriceAlertsRow) {
	ids := make([]uuid.UUID, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.PriceAlert.ID)
	}
	if err := q.TouchPriceAlerts(ctx, ids); err != nil {
		log.Printf("price alerts: touch failed: %v", err)
	}
}

// settle applies one search result to one alert: record the check, and
// notify if the trigger condition is met. MarkPriceAlertNotified runs BEFORE
// the send so a crashed/retried send can never double-notify.
func (c *alertChecker) settle(ctx context.Context, q *store.Queries, row store.ListDuePriceAlertsRow, lowest FlightOffer) {
	a := row.PriceAlert
	// A cross-currency offer is unusable: never write its price into the row
	// (it would display under the wrong currency label and poison the
	// baseline) — just advance the timestamp.
	if a.Currency != nil && *a.Currency != "" && *a.Currency != lowest.Currency {
		c.touch(ctx, q, []store.ListDuePriceAlertsRow{row})
		return
	}
	notify := evaluateAlert(a, lowest.Price, lowest.Currency)

	if err := q.MarkPriceAlertChecked(ctx, store.MarkPriceAlertCheckedParams{
		ID: a.ID, LastCheckedPrice: &lowest.Price, Currency: &lowest.Currency,
	}); err != nil {
		log.Printf("price alerts: mark checked %s: %v", a.ID, err)
		return
	}
	if !notify {
		return
	}
	if err := q.MarkPriceAlertNotified(ctx, store.MarkPriceAlertNotifiedParams{
		ID: a.ID, LastNotifiedPrice: &lowest.Price,
	}); err != nil {
		log.Printf("price alerts: mark notified %s: %v", a.ID, err)
		return
	}
	go sendAlertEmail(row.OwnerEmail, a, lowest)
	tripID := tripIDPtr(a)
	go recordEvent(a.UserID, "alert_triggered", tripID, map[string]any{
		"origin": a.Origin, "destination": a.Destination,
		"price": lowest.Price, "currency": lowest.Currency,
		"target_price": a.TargetPrice,
	})
}

// evaluateAlert decides whether the freshly observed lowest price should
// notify the owner. Pure — the unit-test target. Callers must have already
// excluded cross-currency offers (settle touches those without recording).
func evaluateAlert(a store.PriceAlert, lowestPrice float64, lowestCurrency string) bool {
	if a.Currency != nil && *a.Currency != "" && *a.Currency != lowestCurrency {
		return false
	}
	// Idempotency: only a real further drop below the last notified price
	// can notify again.
	if a.LastNotifiedPrice != nil && lowestPrice > *a.LastNotifiedPrice-notifyEpsilon {
		return false
	}
	if a.TargetPrice != nil {
		return lowestPrice <= *a.TargetPrice
	}
	// Any-drop compares against a FIXED reference — the last notified price,
	// else the creation/first-check baseline — never the rolling last check,
	// so slow cumulative declines accumulate toward the threshold and a
	// spike-then-revert can't notify above what the user was watching.
	ref := a.BaselinePrice
	if a.LastNotifiedPrice != nil {
		ref = a.LastNotifiedPrice
	}
	if ref == nil {
		// First check: record the baseline only.
		return false
	}
	return lowestPrice <= *ref-minDropAbs && lowestPrice <= *ref*(1-minDropFraction)
}

// alertSearchKey collapses alerts that would issue an identical Duffel
// search into one group.
func alertSearchKey(a store.PriceAlert) string {
	return strings.Join([]string{
		a.Origin, a.Destination, dateString(a.DepartDate), dateString(a.ReturnDate),
		a.CabinClass, strconv.Itoa(int(a.Adults)),
	}, "|")
}

// lowestOffer returns the cheapest offer of a search.
func lowestOffer(offers []FlightOffer) (FlightOffer, bool) {
	if len(offers) == 0 {
		return FlightOffer{}, false
	}
	best := offers[0]
	for _, o := range offers[1:] {
		if o.Price < best.Price {
			best = o
		}
	}
	return best, true
}

// buildAlertEmail renders the notification. Pure — unit-tested.
func buildAlertEmail(a store.PriceAlert, lowest FlightOffer) (subject, body string) {
	route := fmt.Sprintf("%s → %s", a.Origin, a.Destination)
	price := fmt.Sprintf("%s %.0f", lowest.Currency, lowest.Price)
	if a.TargetPrice != nil {
		subject = fmt.Sprintf("Target price hit: %s now %s", route, price)
	} else {
		subject = fmt.Sprintf("Price drop: %s now %s", route, price)
	}

	var b strings.Builder
	fmt.Fprintf(&b, "Good news — the fare you're watching dropped.\n\n")
	fmt.Fprintf(&b, "Route: %s\n", route)
	fmt.Fprintf(&b, "Departing: %s\n", dateString(a.DepartDate))
	if ret := dateString(a.ReturnDate); ret != "" {
		fmt.Fprintf(&b, "Returning: %s\n", ret)
	}
	fmt.Fprintf(&b, "Cabin: %s · Adults: %d\n", a.CabinClass, a.Adults)
	fmt.Fprintf(&b, "\nBest price now: %s", price)
	if len(lowest.Airlines) > 0 {
		fmt.Fprintf(&b, " on %s", strings.Join(lowest.Airlines, "/"))
	}
	b.WriteString("\n")
	if a.TargetPrice != nil {
		fmt.Fprintf(&b, "Your target: %s %.0f\n", lowest.Currency, *a.TargetPrice)
	} else if a.LastCheckedPrice != nil {
		fmt.Fprintf(&b, "Previously: %s %.0f\n", lowest.Currency, *a.LastCheckedPrice)
	}
	fmt.Fprintf(&b, "\nSearch it again and book: %s\n", publicAppURL("alerts"))
	b.WriteString("\nPrices change frequently and this fare may not last. ")
	b.WriteString("Manage or mute this alert under Price alerts in the app.\n")
	return subject, b.String()
}

func sendAlertEmail(to string, a store.PriceAlert, lowest FlightOffer) {
	subject, body := buildAlertEmail(a, lowest)
	if err := emailService.Send(to, subject, body); err != nil {
		log.Printf("price alerts: email to %s failed: %v", to, err)
	}
}

// --- small conversion helpers ---

// dateString renders a pgtype.Date as YYYY-MM-DD, "" when unset.
func dateString(d pgtype.Date) string {
	if !d.Valid {
		return ""
	}
	return d.Time.Format(dateLayout)
}

func pgTimestamptz(t time.Time) pgtype.Timestamptz {
	return pgtype.Timestamptz{Time: t, Valid: true}
}

func tripIDPtr(a store.PriceAlert) *uuid.UUID {
	if !a.TripID.Valid {
		return nil
	}
	id := uuid.UUID(a.TripID.Bytes)
	return &id
}
