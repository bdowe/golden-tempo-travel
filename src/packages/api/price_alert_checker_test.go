package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

func strp(s string) *string { return &s }

func alertFixture(mutate func(*store.PriceAlert)) store.PriceAlert {
	a := store.PriceAlert{
		Origin: "BOS", Destination: "CDG",
		DepartDate: pgtype.Date{Time: time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC), Valid: true},
		CabinClass: "economy", Adults: 1, Status: "active",
	}
	if mutate != nil {
		mutate(&a)
	}
	return a
}

func TestEvaluateAlertTargetMode(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*store.PriceAlert)
		price  float64
		want   bool
	}{
		{"target crossed", func(a *store.PriceAlert) { a.TargetPrice = f64(450) }, 412, true},
		{"target exactly met", func(a *store.PriceAlert) { a.TargetPrice = f64(450) }, 450, true},
		{"above target", func(a *store.PriceAlert) { a.TargetPrice = f64(450) }, 470, false},
		{"same price after notify", func(a *store.PriceAlert) {
			a.TargetPrice = f64(450)
			a.LastNotifiedPrice = f64(412)
		}, 412, false},
		{"further drop after notify", func(a *store.PriceAlert) {
			a.TargetPrice = f64(450)
			a.LastNotifiedPrice = f64(412)
		}, 380, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := evaluateAlert(alertFixture(tc.mutate), tc.price, "USD"); got != tc.want {
				t.Fatalf("evaluateAlert = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestEvaluateAlertAnyDropMode(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*store.PriceAlert)
		price  float64
		want   bool
	}{
		{"no baseline yet records only", nil, 400, false},
		{"real drop", func(a *store.PriceAlert) { a.BaselinePrice = f64(500) }, 450, true},
		{"under 5 percent", func(a *store.PriceAlert) { a.BaselinePrice = f64(500) }, 480, false},
		// 4 < $5 absolute even though >= 5% of a small fare.
		{"under 5 dollars", func(a *store.PriceAlert) { a.BaselinePrice = f64(60) }, 56, false},
		{"jitter up never notifies", func(a *store.PriceAlert) { a.BaselinePrice = f64(500) }, 520, false},
		// The reference is FIXED: a rolling last-checked price must not
		// mask a slow cumulative decline...
		{"cumulative decline notifies vs baseline", func(a *store.PriceAlert) {
			a.BaselinePrice = f64(500)
			a.LastCheckedPrice = f64(445) // previous check, already lower
		}, 430, true},
		// ...and a recorded spike must not turn a revert into a "drop".
		{"spike then revert never notifies above baseline", func(a *store.PriceAlert) {
			a.BaselinePrice = f64(600)
			a.LastCheckedPrice = f64(800) // spike recorded by a prior check
		}, 640, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := evaluateAlert(alertFixture(tc.mutate), tc.price, "USD"); got != tc.want {
				t.Fatalf("evaluateAlert = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestEvaluateAlertCurrencyMismatch(t *testing.T) {
	a := alertFixture(func(a *store.PriceAlert) {
		a.Currency = strp("USD")
		a.TargetPrice = f64(450)
	})
	if evaluateAlert(a, 100, "EUR") {
		t.Fatal("cross-currency comparison must never notify")
	}
}

func TestFlexSearchKeyGrouping(t *testing.T) {
	base := FlightSearchRequest{Origin: "BOS", Destination: "CDG",
		DepartDate: "2026-09-01", CabinClass: "economy", Adults: 1}
	same := base
	if flexSearchKey(base) != flexSearchKey(same) {
		t.Fatal("identical searches must share a key")
	}
	adults := base
	adults.Adults = 2
	if flexSearchKey(base) == flexSearchKey(adults) {
		t.Fatal("different adults must not share a key")
	}
	cabin := base
	cabin.CabinClass = "business"
	if flexSearchKey(base) == flexSearchKey(cabin) {
		t.Fatal("different cabin must not share a key")
	}
	date := base
	date.DepartDate = "2026-09-02"
	if flexSearchKey(base) == flexSearchKey(date) {
		t.Fatal("different depart date must not share a key")
	}
}

// A flexible alert and an exact alert that price the same route+date share
// that dated search (flex_days is intentionally not part of the key).
func TestFlexCandidatesShareExactDate(t *testing.T) {
	depart := time.Now().AddDate(0, 1, 0)
	exact := alertFixture(func(a *store.PriceAlert) {
		a.DepartDate = pgtype.Date{Time: depart, Valid: true}
	})
	flex := alertFixture(func(a *store.PriceAlert) {
		a.DepartDate = pgtype.Date{Time: depart, Valid: true}
		a.FlexDays = 1
	})
	exactCands := flexCandidates(exact, time.Now())
	flexCands := flexCandidates(flex, time.Now())
	if len(exactCands) != 1 {
		t.Fatalf("exact alert expanded to %d candidates, want 1", len(exactCands))
	}
	if len(flexCands) != 3 {
		t.Fatalf("±1 alert expanded to %d candidates, want 3", len(flexCands))
	}
	// The exact date's key must appear in the flexible window.
	found := false
	for _, c := range flexCands {
		if c.key == exactCands[0].key {
			found = true
		}
	}
	if !found {
		t.Fatal("flexible window must share the exact date's search key")
	}
}

// Candidate dates before today are dropped — never search a departed flight.
func TestFlexCandidatesSkipsPast(t *testing.T) {
	today := time.Now()
	// Depart today with ±3: only today..+3 are valid (4 candidates).
	a := alertFixture(func(a *store.PriceAlert) {
		a.DepartDate = pgtype.Date{Time: today, Valid: true}
		a.FlexDays = 3
	})
	cands := flexCandidates(a, today)
	if len(cands) != 4 {
		t.Fatalf("±3 window on a today-departure yielded %d candidates, want 4 (no past dates)", len(cands))
	}
	todayStr := today.Format(dateLayout)
	for _, c := range cands {
		if c.req.DepartDate < todayStr {
			t.Fatalf("past candidate not skipped: %s", c.req.DepartDate)
		}
	}
}

func TestLowestOffer(t *testing.T) {
	if _, ok := lowestOffer(nil); ok {
		t.Fatal("empty offers must report not-ok")
	}
	best, ok := lowestOffer([]FlightOffer{{Price: 500}, {Price: 412}, {Price: 470}})
	if !ok || best.Price != 412 {
		t.Fatalf("lowestOffer = %v %v, want 412", best.Price, ok)
	}
}

func TestBuildAlertEmail(t *testing.T) {
	t.Setenv("PUBLIC_BASE_URL", "https://app.example.com")
	a := alertFixture(func(a *store.PriceAlert) { a.TargetPrice = f64(450) })
	subject, body := buildAlertEmail("en", a, FlightOffer{Price: 412, Currency: "USD", Airlines: []string{"Air France"}}, pgtype.Date{})

	if !strings.Contains(subject, "Target price hit") || !strings.Contains(subject, "BOS → CDG") {
		t.Fatalf("subject = %q", subject)
	}
	for _, want := range []string{"USD 412", "Air France", "2026-09-01", "https://app.example.com", "alerts"} {
		if !strings.Contains(body, want) {
			t.Fatalf("body missing %q:\n%s", want, body)
		}
	}
}

func TestValidateCreateAlert(t *testing.T) {
	today := time.Date(2026, 7, 5, 12, 0, 0, 0, time.UTC)
	valid := func() CreatePriceAlertRequest {
		return CreatePriceAlertRequest{Origin: "bos", Destination: "cdg", DepartDate: "2026-09-01"}
	}

	req := valid()
	if err := validateCreateAlert(&req, today); err != nil {
		t.Fatalf("valid request rejected: %v", err)
	}
	if req.Origin != "BOS" || req.CabinClass != "economy" || req.Adults != 1 {
		t.Fatalf("normalization wrong: %+v", req)
	}

	bad := []func(*CreatePriceAlertRequest){
		func(r *CreatePriceAlertRequest) { r.Origin = "BOST" },
		func(r *CreatePriceAlertRequest) { r.Destination = "B1S" },
		func(r *CreatePriceAlertRequest) { r.Destination = "BOS" },
		func(r *CreatePriceAlertRequest) { r.DepartDate = "yesterday" },
		func(r *CreatePriceAlertRequest) { r.DepartDate = "2026-07-01" },
		func(r *CreatePriceAlertRequest) { r.ReturnDate = strp("2026-08-01") },
		func(r *CreatePriceAlertRequest) { r.CabinClass = "steerage" },
		func(r *CreatePriceAlertRequest) { r.Adults = 12 },
		func(r *CreatePriceAlertRequest) { r.TargetPrice = f64(-5) },
		func(r *CreatePriceAlertRequest) { r.FlexDays = 4 },  // above the ±3 cap
		func(r *CreatePriceAlertRequest) { r.FlexDays = -1 }, // negative window
	}
	for i, mutate := range bad {
		r := valid()
		mutate(&r)
		if err := validateCreateAlert(&r, today); err == nil {
			t.Fatalf("bad case %d accepted: %+v", i, r)
		}
	}

	// flex_days within the cap is accepted.
	for _, fd := range []int{0, 1, 2, 3} {
		r := valid()
		r.FlexDays = fd
		if err := validateCreateAlert(&r, today); err != nil {
			t.Fatalf("flex_days=%d rejected: %v", fd, err)
		}
	}
}

// stubDuffelOffers returns a DuffelService whose every search yields one
// offer at the given price.
func stubDuffelOffers(t *testing.T, price string, calls *int) *DuffelService {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*calls++
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"data":{"offers":[{
			"id":"off_1","total_amount":"` + price + `","total_currency":"USD",
			"owner":{"iata_code":"AF","name":"Air France"},
			"slices":[{"duration":"PT8H","segments":[{
				"origin":{"iata_code":"BOS"},"destination":{"iata_code":"CDG"},
				"departing_at":"2026-09-01T18:00:00","arriving_at":"2026-09-02T07:00:00",
				"marketing_carrier":{"name":"Air France","iata_code":"AF"},
				"marketing_carrier_flight_number":"332"}]}]}]}}`))
	}))
	t.Cleanup(srv.Close)
	return &DuffelService{Token: "test-token", BaseURL: srv.URL, Version: "v2",
		Client: &http.Client{Timeout: 5 * time.Second}}
}

// End-to-end checker pass against the integration DB: two users watching the
// same route cost ONE Duffel search; the target-mode alert notifies (marked
// before send), the any-drop alert with no baseline only records.
func TestAlertCheckerRunOnce(t *testing.T) {
	resetDB(t)
	userA, _ := createTestUser(t, "watcher-a@example.com")
	userB, _ := createTestUser(t, "watcher-b@example.com")

	depart := time.Now().AddDate(0, 2, 0).Truncate(24 * time.Hour)
	mkAlert := func(u store.User, target *float64) {
		t.Helper()
		_, err := store.New(dbPool).CreatePriceAlert(context.Background(), store.CreatePriceAlertParams{
			UserID: u.ID, Origin: "BOS", Destination: "CDG",
			DepartDate: pgtype.Date{Time: depart, Valid: true},
			CabinClass: "economy", Adults: 1, TargetPrice: target,
			Baggage: baggagePersonalItem,
		})
		if err != nil {
			t.Fatalf("seed alert: %v", err)
		}
	}
	mkAlert(userA, f64(450)) // target mode: 412 <= 450 → notify
	mkAlert(userB, nil)      // any-drop, no baseline → record only

	calls := 0
	c := &alertChecker{
		duffel:     stubDuffelOffers(t, "412.00", &calls),
		checkEvery: 6 * time.Hour,
		batchSize:  25,
		perCallGap: 0,
	}
	c.runOnce(context.Background())

	if calls != 1 {
		t.Fatalf("Duffel searches = %d, want 1 (route dedupe)", calls)
	}

	alerts, err := store.New(dbPool).ListPriceAlertsByUser(context.Background(), userA.ID)
	if err != nil || len(alerts) != 1 {
		t.Fatalf("load alerts: %v (%d)", err, len(alerts))
	}
	a := alerts[0]
	if a.LastCheckedPrice == nil || *a.LastCheckedPrice != 412 || !a.LastCheckedAt.Valid {
		t.Fatalf("target alert not marked checked: %+v", a)
	}
	if a.LastNotifiedPrice == nil || *a.LastNotifiedPrice != 412 {
		t.Fatalf("target alert not marked notified: %+v", a)
	}

	bAlerts, _ := store.New(dbPool).ListPriceAlertsByUser(context.Background(), userB.ID)
	b := bAlerts[0]
	if b.LastCheckedPrice == nil || *b.LastCheckedPrice != 412 {
		t.Fatalf("any-drop alert not baseline-recorded: %+v", b)
	}
	if b.LastNotifiedPrice != nil {
		t.Fatalf("any-drop alert notified without baseline: %+v", b)
	}

	// Second pass inside the freshness window: nothing due, no new search.
	c.runOnce(context.Background())
	if calls != 1 {
		t.Fatalf("freshness window ignored: %d searches", calls)
	}
}

// A triggered drop persists exactly one notifications row (type 'price_drop')
// with the values the email gets; a non-drop check persists none; a re-check at
// the same price persists none (the v1 notify idempotency covers notifications
// too). Wave 16 cutover: the checker writes `notifications`, not alert_events.
func TestAlertCheckerInsertsEvents(t *testing.T) {
	resetDB(t)
	userA, _ := createTestUser(t, "events-a@example.com")
	userB, _ := createTestUser(t, "events-b@example.com")
	q := store.New(dbPool)

	depart := time.Now().AddDate(0, 2, 0).Truncate(24 * time.Hour)
	usd := "USD"
	// Target-mode alert seeded with the price the user was looking at, aged
	// past the freshness window so it is due immediately. 412 <= 450 → notify.
	alertA, err := q.CreatePriceAlert(context.Background(), store.CreatePriceAlertParams{
		UserID: userA.ID, Origin: "BOS", Destination: "CDG",
		DepartDate: pgtype.Date{Time: depart, Valid: true},
		CabinClass: "economy", Adults: 1, TargetPrice: f64(450),
		Baggage:          baggagePersonalItem,
		LastCheckedPrice: f64(498), Currency: &usd,
		LastCheckedAt: pgTimestamptz(time.Now().Add(-7 * time.Hour)),
	})
	if err != nil {
		t.Fatalf("seed alert A: %v", err)
	}
	// Any-drop alert with no baseline: the first check records only.
	if _, err := q.CreatePriceAlert(context.Background(), store.CreatePriceAlertParams{
		UserID: userB.ID, Origin: "BOS", Destination: "CDG",
		DepartDate: pgtype.Date{Time: depart, Valid: true},
		CabinClass: "economy", Adults: 1, Baggage: baggagePersonalItem,
	}); err != nil {
		t.Fatalf("seed alert B: %v", err)
	}

	calls := 0
	c := &alertChecker{
		duffel:     stubDuffelOffers(t, "412.00", &calls),
		checkEvery: 6 * time.Hour,
		batchSize:  25,
		perCallGap: 0,
	}
	c.runOnce(context.Background())

	eventsFor := func(u store.User) []store.Notification {
		t.Helper()
		rows, err := q.ListNotificationsByUser(context.Background(),
			store.ListNotificationsByUserParams{UserID: u.ID, Limit: 10})
		if err != nil {
			t.Fatalf("list notifications: %v", err)
		}
		return rows
	}

	got := eventsFor(userA)
	if len(got) != 1 {
		t.Fatalf("triggered drop notifications = %d, want exactly 1", len(got))
	}
	ev := got[0]
	if ev.Type != "price_drop" {
		t.Fatalf("notification type = %q, want price_drop", ev.Type)
	}
	var p map[string]any
	if err := json.Unmarshal(ev.Payload, &p); err != nil {
		t.Fatalf("payload not JSON: %v (%s)", err, ev.Payload)
	}
	if p["alert_id"] != alertA.ID.String() || p["price"] != 412.0 || p["currency"] != "USD" {
		t.Fatalf("payload values wrong: %v", p)
	}
	if p["previous_price"] != 498.0 {
		t.Fatalf("previous_price = %v, want 498 (the seeded reference)", p["previous_price"])
	}
	if p["origin"] != "BOS" || p["destination"] != "CDG" || p["depart_date"] == "" {
		t.Fatalf("route context missing from payload: %v", p)
	}
	if ev.ReadAt.Valid {
		t.Fatalf("fresh notification must be unread: %+v", ev)
	}
	if n := len(eventsFor(userB)); n != 0 {
		t.Fatalf("non-drop check inserted %d notifications, want 0", n)
	}

	// Force both alerts due again and re-check at the same price: no further
	// drop for A (last notified 412), no 5%+$5 drop for B (baseline now 412).
	if _, err := dbPool.Exec(context.Background(),
		`UPDATE price_alerts SET last_checked_at = now() - interval '7 hours'`); err != nil {
		t.Fatalf("age alerts: %v", err)
	}
	c.runOnce(context.Background())
	if n := len(eventsFor(userA)); n != 1 {
		t.Fatalf("re-check without a new drop inserted events: %d, want 1", n)
	}
	if n := len(eventsFor(userB)); n != 0 {
		t.Fatalf("re-check inserted events for the any-drop alert: %d, want 0", n)
	}
}

// stubDuffelByDate prices each search by its requested departure_date (falling
// back to base), so a flexible fan-out can be checked for cheapest-date logic.
func stubDuffelByDate(t *testing.T, base string, byDate map[string]string, calls *int) *DuffelService {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		*calls++
		var body struct {
			Data struct {
				Slices []struct {
					DepartureDate string `json:"departure_date"`
				} `json:"slices"`
			} `json:"data"`
		}
		_ = json.NewDecoder(r.Body).Decode(&body)
		date := ""
		if len(body.Data.Slices) > 0 {
			date = body.Data.Slices[0].DepartureDate
		}
		price := base
		if p, ok := byDate[date]; ok {
			price = p
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"data":{"offers":[{
			"id":"off_1","total_amount":"` + price + `","total_currency":"USD",
			"owner":{"iata_code":"AF","name":"Air France"},
			"slices":[{"duration":"PT8H","segments":[{
				"origin":{"iata_code":"BOS"},"destination":{"iata_code":"CDG"},
				"departing_at":"` + date + `T18:00:00","arriving_at":"2026-09-02T07:00:00",
				"marketing_carrier":{"name":"Air France","iata_code":"AF"},
				"marketing_carrier_flight_number":"332"}]}]}]}}`))
	}))
	t.Cleanup(srv.Close)
	return &DuffelService{Token: "test-token", BaseURL: srv.URL, Version: "v2",
		Client: &http.Client{Timeout: 5 * time.Second}}
}

// A ±1 flexible alert issues one Duffel search per date in its window (3),
// picks the cheapest date, records it as matched_departure_date on the event,
// and marks the alert checked at that cheapest price.
func TestAlertCheckerFlexFanOut(t *testing.T) {
	resetDB(t)
	user, _ := createTestUser(t, "flex@example.com")

	depart := time.Now().AddDate(0, 2, 0).Truncate(24 * time.Hour)
	dayBefore := depart.AddDate(0, 0, -1)
	dayAfter := depart.AddDate(0, 0, 1)
	fmtd := func(x time.Time) string { return x.Format(dateLayout) }

	q := store.New(dbPool)
	if _, err := q.CreatePriceAlert(context.Background(), store.CreatePriceAlertParams{
		UserID: user.ID, Origin: "BOS", Destination: "CDG",
		DepartDate: pgtype.Date{Time: depart, Valid: true},
		CabinClass: "economy", Adults: 1, TargetPrice: f64(450), FlexDays: 1,
		Baggage: baggagePersonalItem,
	}); err != nil {
		t.Fatalf("seed flex alert: %v", err)
	}

	// The day before is the cheapest at 400 (<= target 450 → notify); the
	// nominal date and the day after are pricier and must lose.
	calls := 0
	c := &alertChecker{
		duffel: stubDuffelByDate(t, "500.00", map[string]string{
			fmtd(dayBefore): "400.00",
			fmtd(depart):    "500.00",
			fmtd(dayAfter):  "480.00",
		}, &calls),
		checkEvery: 6 * time.Hour,
		batchSize:  25,
		perCallGap: 0,
	}
	c.runOnce(context.Background())

	if calls != 3 {
		t.Fatalf("±1 alert issued %d Duffel searches, want 3 (one per date)", calls)
	}

	rows, err := q.ListNotificationsByUser(context.Background(),
		store.ListNotificationsByUserParams{UserID: user.ID, Limit: 10})
	if err != nil {
		t.Fatalf("list notifications: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("flex trigger notifications = %d, want 1", len(rows))
	}
	var p map[string]any
	if err := json.Unmarshal(rows[0].Payload, &p); err != nil {
		t.Fatalf("payload not JSON: %v (%s)", err, rows[0].Payload)
	}
	if p["price"] != 400.0 {
		t.Fatalf("notification price = %v, want 400 (cheapest date)", p["price"])
	}
	if p["matched_date"] != fmtd(dayBefore) {
		t.Fatalf("matched_date = %v, want %q", p["matched_date"], fmtd(dayBefore))
	}

	alerts, _ := q.ListPriceAlertsByUser(context.Background(), user.ID)
	a := alerts[0]
	if a.LastCheckedPrice == nil || *a.LastCheckedPrice != 400 {
		t.Fatalf("alert not checked at cheapest price: %+v", a.LastCheckedPrice)
	}
	if a.LastNotifiedPrice == nil || *a.LastNotifiedPrice != 400 {
		t.Fatalf("alert not notified at cheapest price: %+v", a.LastNotifiedPrice)
	}
}

// The per-cycle batch limiter bounds provider calls even under fan-out: a ±1
// alert (3 searches) against a batchSize of 2 issues only 2 searches, and the
// alert whose window was left incomplete is deferred (not checked/notified),
// staying at the front of the due queue for the next cycle.
func TestAlertCheckerFlexRespectsBatchLimit(t *testing.T) {
	resetDB(t)
	user, _ := createTestUser(t, "flex-batch@example.com")

	depart := time.Now().AddDate(0, 2, 0).Truncate(24 * time.Hour)
	q := store.New(dbPool)
	if _, err := q.CreatePriceAlert(context.Background(), store.CreatePriceAlertParams{
		UserID: user.ID, Origin: "BOS", Destination: "CDG",
		DepartDate: pgtype.Date{Time: depart, Valid: true},
		CabinClass: "economy", Adults: 1, TargetPrice: f64(450), FlexDays: 1,
		Baggage: baggagePersonalItem,
	}); err != nil {
		t.Fatalf("seed flex alert: %v", err)
	}

	calls := 0
	c := &alertChecker{
		duffel:     stubDuffelOffers(t, "400.00", &calls),
		checkEvery: 6 * time.Hour,
		batchSize:  2, // fewer than the window's 3 searches
		perCallGap: 0,
	}
	c.runOnce(context.Background())

	if calls != 2 {
		t.Fatalf("batch limit ignored: %d searches, want 2", calls)
	}
	alerts, _ := q.ListPriceAlertsByUser(context.Background(), user.ID)
	a := alerts[0]
	if a.LastCheckedAt.Valid {
		t.Fatalf("partially-searched flex alert must stay un-checked (deferred), got last_checked_at set")
	}
	if a.LastNotifiedPrice != nil {
		t.Fatalf("deferred flex alert must not notify: %+v", a.LastNotifiedPrice)
	}
	if n, _ := q.CountUnreadAlertEvents(context.Background(), user.ID); n != 0 {
		t.Fatalf("deferred flex alert wrote %d events, want 0", n)
	}
}
