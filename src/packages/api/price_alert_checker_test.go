package main

import (
	"context"
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

func TestAlertSearchKeyGrouping(t *testing.T) {
	a := alertFixture(nil)
	b := alertFixture(nil)
	if alertSearchKey(a) != alertSearchKey(b) {
		t.Fatal("identical searches must share a key")
	}
	c := alertFixture(func(x *store.PriceAlert) { x.Adults = 2 })
	if alertSearchKey(a) == alertSearchKey(c) {
		t.Fatal("different adults must not share a key")
	}
	d := alertFixture(func(x *store.PriceAlert) { x.CabinClass = "business" })
	if alertSearchKey(a) == alertSearchKey(d) {
		t.Fatal("different cabin must not share a key")
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
	subject, body := buildAlertEmail(a, FlightOffer{Price: 412, Currency: "USD", Airlines: []string{"Air France"}})

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
	}
	for i, mutate := range bad {
		r := valid()
		mutate(&r)
		if err := validateCreateAlert(&r, today); err == nil {
			t.Fatalf("bad case %d accepted: %+v", i, r)
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
