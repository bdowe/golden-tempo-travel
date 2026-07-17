package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// Price-alert CRUD (specs/price-alerts). All routes require auth; creation
// sits on the strict rate tier.

// maxActiveAlertsPerUser bounds provider cost per user. This is also where a
// future paid tier would raise the line (docs/business-model.md §4) — it is
// a cost bound today, not a paywall.
const maxActiveAlertsPerUser = 10

// maxAlertFlexDays hard-caps departure flexibility. A flexible alert fans out
// to 2N+1 exact-date Duffel searches per cycle, so this bound is what keeps
// provider spend linear and finite (specs/price-alerts-v2 cost budget).
const maxAlertFlexDays = 3

type CreatePriceAlertRequest struct {
	Origin       string   `json:"origin"`
	Destination  string   `json:"destination"`
	DepartDate   string   `json:"depart_date"`
	ReturnDate   *string  `json:"return_date"`
	CabinClass   string   `json:"cabin_class"`
	Adults       int      `json:"adults"`
	TargetPrice  *float64 `json:"target_price"`
	CurrentPrice *float64 `json:"current_price"`
	Currency     *string  `json:"currency"`
	TripID       *string  `json:"trip_id"`
	// FlexDays is the departure-window half-width (0–3). 0 (the default) is
	// the exact-date behavior; N>0 watches [depart-N, depart+N]. Capped
	// server-side because each extra day multiplies provider searches.
	FlexDays int `json:"flex_days"`
}

type PriceAlertResponse struct {
	ID                string   `json:"id"`
	Origin            string   `json:"origin"`
	Destination       string   `json:"destination"`
	DepartDate        string   `json:"depart_date"`
	ReturnDate        *string  `json:"return_date"`
	CabinClass        string   `json:"cabin_class"`
	Adults            int      `json:"adults"`
	TargetPrice       *float64 `json:"target_price"`
	FlexDays          int      `json:"flex_days"`
	Currency          *string  `json:"currency"`
	BaselinePrice     *float64 `json:"baseline_price"`
	LastCheckedPrice  *float64 `json:"last_checked_price"`
	LastCheckedAt     *string  `json:"last_checked_at"`
	LastNotifiedPrice *float64 `json:"last_notified_price"`
	LastNotifiedAt    *string  `json:"last_notified_at"`
	Status            string   `json:"status"`
	TripID            *string  `json:"trip_id"`
	CreatedAt         string   `json:"created_at"`
}

func toPriceAlertResponse(a store.PriceAlert) PriceAlertResponse {
	resp := PriceAlertResponse{
		ID:                a.ID.String(),
		Origin:            a.Origin,
		Destination:       a.Destination,
		DepartDate:        dateString(a.DepartDate),
		CabinClass:        a.CabinClass,
		Adults:            int(a.Adults),
		TargetPrice:       a.TargetPrice,
		FlexDays:          int(a.FlexDays),
		Currency:          a.Currency,
		BaselinePrice:     a.BaselinePrice,
		LastCheckedPrice:  a.LastCheckedPrice,
		LastNotifiedPrice: a.LastNotifiedPrice,
		Status:            a.Status,
		CreatedAt:         a.CreatedAt.Format(time.RFC3339),
	}
	if ret := dateString(a.ReturnDate); ret != "" {
		resp.ReturnDate = &ret
	}
	if a.LastCheckedAt.Valid {
		s := a.LastCheckedAt.Time.Format(time.RFC3339)
		resp.LastCheckedAt = &s
	}
	if a.LastNotifiedAt.Valid {
		s := a.LastNotifiedAt.Time.Format(time.RFC3339)
		resp.LastNotifiedAt = &s
	}
	if a.TripID.Valid {
		s := uuid.UUID(a.TripID.Bytes).String()
		resp.TripID = &s
	}
	return resp
}

// validateCreateAlert normalizes and validates a create request. Pure — the
// unit-test target. Mirrors flight-search validation.
func validateCreateAlert(req *CreatePriceAlertRequest, today time.Time) error {
	req.Origin = strings.ToUpper(strings.TrimSpace(req.Origin))
	req.Destination = strings.ToUpper(strings.TrimSpace(req.Destination))
	if len(req.Origin) != 3 || !isAlpha(req.Origin) || len(req.Destination) != 3 || !isAlpha(req.Destination) {
		return fmt.Errorf("origin and destination must be 3-letter IATA codes")
	}
	if req.Origin == req.Destination {
		return fmt.Errorf("origin and destination must differ")
	}
	depart, err := time.Parse(dateLayout, req.DepartDate)
	if err != nil {
		return fmt.Errorf("depart_date must be YYYY-MM-DD")
	}
	// Compare calendar dates as strings — Truncate(24h) works on UTC epoch
	// boundaries and misjudges "today" on any non-UTC server.
	if req.DepartDate < today.Format(dateLayout) {
		return fmt.Errorf("depart_date must be today or later")
	}
	if req.ReturnDate != nil && *req.ReturnDate != "" {
		ret, err := time.Parse(dateLayout, *req.ReturnDate)
		if err != nil {
			return fmt.Errorf("return_date must be YYYY-MM-DD")
		}
		if ret.Before(depart) {
			return fmt.Errorf("return_date must be on or after depart_date")
		}
	} else {
		req.ReturnDate = nil
	}
	req.CabinClass = strings.ToLower(strings.TrimSpace(req.CabinClass))
	if req.CabinClass == "" {
		req.CabinClass = "economy"
	}
	if !allowedCabinClasses[req.CabinClass] {
		return fmt.Errorf("cabin_class must be one of: 'economy', 'premium_economy', 'business', 'first'")
	}
	if req.Adults == 0 {
		req.Adults = 1
	}
	if req.Adults < 1 || req.Adults > 9 {
		return fmt.Errorf("adults must be between 1 and 9")
	}
	if req.TargetPrice != nil && *req.TargetPrice <= 0 {
		return fmt.Errorf("target_price must be positive")
	}
	// Flexibility is hard-capped: each extra day multiplies provider searches
	// (2N+1 per cycle), so the window can only ever be ±3 days.
	if req.FlexDays < 0 || req.FlexDays > maxAlertFlexDays {
		return fmt.Errorf("flex_days must be between 0 and %d", maxAlertFlexDays)
	}
	if req.CurrentPrice != nil && *req.CurrentPrice <= 0 {
		req.CurrentPrice = nil
	}
	return nil
}

func createPriceAlertHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())

	var req CreatePriceAlertRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if err := validateCreateAlert(&req, time.Now()); err != nil {
		writeJSONError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}

	q := store.New(dbPool)
	if n, err := q.CountActivePriceAlertsByUser(r.Context(), user.ID); err == nil && n >= maxActiveAlertsPerUser {
		writeJSONError(w, http.StatusUnprocessableEntity,
			fmt.Sprintf("alert limit reached (%d active alerts) — pause or delete one first", maxActiveAlertsPerUser))
		return
	}

	params := store.CreatePriceAlertParams{
		UserID:      user.ID,
		Origin:      req.Origin,
		Destination: req.Destination,
		CabinClass:  req.CabinClass,
		Adults:      int32(req.Adults),
		TargetPrice: req.TargetPrice,
		FlexDays:    int16(req.FlexDays),
	}
	depart, _ := time.Parse(dateLayout, req.DepartDate)
	params.DepartDate = pgtype.Date{Time: depart, Valid: true}
	if req.ReturnDate != nil {
		ret, _ := time.Parse(dateLayout, *req.ReturnDate)
		params.ReturnDate = pgtype.Date{Time: ret, Valid: true}
	}
	if req.TripID != nil {
		if tid, err := uuid.Parse(*req.TripID); err == nil {
			params.TripID = pgtype.UUID{Bytes: tid, Valid: true}
		}
	}
	// The search result the user was looking at seeds the any-drop baseline
	// so the first checker pass can already compare.
	if req.CurrentPrice != nil && req.Currency != nil && *req.Currency != "" {
		params.LastCheckedPrice = req.CurrentPrice
		cur := strings.ToUpper(strings.TrimSpace(*req.Currency))
		params.Currency = &cur
		params.LastCheckedAt = pgTimestamptz(time.Now())
	}

	alert, err := q.CreatePriceAlert(r.Context(), params)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			writeJSONError(w, http.StatusConflict, "you already have an active alert for this exact search")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "could not create alert")
		return
	}

	mode := "any_drop"
	if alert.TargetPrice != nil {
		mode = "target"
	}
	go recordEvent(user.ID, "alert_created", tripIDPtr(alert), map[string]any{
		"origin": alert.Origin, "destination": alert.Destination, "mode": mode,
	})
	writeJSON(w, http.StatusCreated, toPriceAlertResponse(alert))
}

func listPriceAlertsHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	alerts, err := store.New(dbPool).ListPriceAlertsByUser(r.Context(), user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load alerts")
		return
	}
	out := make([]PriceAlertResponse, 0, len(alerts))
	for _, a := range alerts {
		out = append(out, toPriceAlertResponse(a))
	}
	writeJSON(w, http.StatusOK, out)
}

func patchPriceAlertHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	id, err := uuid.Parse(mux.Vars(r)["id"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "alert not found")
		return
	}

	var req struct {
		Status      *string  `json:"status"`
		TargetPrice *float64 `json:"target_price"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	q := store.New(dbPool)
	current, err := q.GetPriceAlertForUser(r.Context(), store.GetPriceAlertForUserParams{ID: id, UserID: user.ID})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeJSONError(w, http.StatusNotFound, "alert not found")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "could not load alert")
		return
	}

	status := current.Status
	if req.Status != nil {
		s := strings.ToLower(strings.TrimSpace(*req.Status))
		if s != "active" && s != "paused" {
			writeJSONError(w, http.StatusBadRequest, "status must be 'active' or 'paused'")
			return
		}
		if current.Status == "expired" {
			writeJSONError(w, http.StatusBadRequest, "an expired alert cannot be reactivated; create a new one")
			return
		}
		status = s
	}
	target := current.TargetPrice
	if req.TargetPrice != nil {
		if *req.TargetPrice <= 0 {
			writeJSONError(w, http.StatusBadRequest, "target_price must be positive")
			return
		}
		target = req.TargetPrice
	}

	updated, err := q.UpdatePriceAlert(r.Context(), store.UpdatePriceAlertParams{
		ID: id, UserID: user.ID, Status: status, TargetPrice: target,
	})
	if err != nil {
		// Resuming can collide with an identical active alert created while
		// this one was paused (the unique index only covers active rows).
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			writeJSONError(w, http.StatusConflict, "you already have an active alert for this exact search — delete one of them")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "could not update alert")
		return
	}
	writeJSON(w, http.StatusOK, toPriceAlertResponse(updated))
}

func deletePriceAlertHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	id, err := uuid.Parse(mux.Vars(r)["id"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "alert not found")
		return
	}
	n, err := store.New(dbPool).DeletePriceAlert(r.Context(), store.DeletePriceAlertParams{ID: id, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not delete alert")
		return
	}
	if n == 0 {
		writeJSONError(w, http.StatusNotFound, "alert not found")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
