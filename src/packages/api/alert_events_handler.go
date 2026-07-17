package main

import (
	"net/http"
	"strconv"
	"time"

	"travel-route-planner/store"
)

// Alert-event read API (specs/price-alerts-v2): the notification-center
// spine. Events are written by the checker (price_alert_checker.go settle);
// this file only reads and marks them. All routes require auth.

const (
	defaultAlertEventsLimit = 50
	maxAlertEventsLimit     = 200
)

// AlertEventResponse is one notification with its alert's route/dates joined
// in, so the client renders a row without a second request.
type AlertEventResponse struct {
	ID            string   `json:"id"`
	AlertID       string   `json:"alert_id"`
	Price         float64  `json:"price"`
	Currency      string   `json:"currency"`
	PreviousPrice *float64 `json:"previous_price"`
	OccurredAt    string   `json:"occurred_at"`
	ReadAt        *string  `json:"read_at"`
	Origin        string   `json:"origin"`
	Destination   string   `json:"destination"`
	DepartDate    string   `json:"depart_date"`
	ReturnDate    *string  `json:"return_date"`
	// MatchedDate is the winning date inside a flexible window; null for an
	// exact-date alert (where it always equals depart_date).
	MatchedDate *string  `json:"matched_date"`
	TargetPrice *float64 `json:"target_price"`
	AlertStatus string   `json:"alert_status"`
}

func toAlertEventResponse(row store.ListAlertEventsByUserRow) AlertEventResponse {
	resp := AlertEventResponse{
		ID:            row.ID.String(),
		AlertID:       row.AlertID.String(),
		Price:         row.Price,
		Currency:      row.Currency,
		PreviousPrice: row.PreviousPrice,
		OccurredAt:    row.OccurredAt.Format(time.RFC3339),
		Origin:        row.Origin,
		Destination:   row.Destination,
		DepartDate:    dateString(row.DepartDate),
		TargetPrice:   row.TargetPrice,
		AlertStatus:   row.AlertStatus,
	}
	if row.ReadAt.Valid {
		s := row.ReadAt.Time.Format(time.RFC3339)
		resp.ReadAt = &s
	}
	if ret := dateString(row.ReturnDate); ret != "" {
		resp.ReturnDate = &ret
	}
	if m := dateString(row.MatchedDepartureDate); m != "" {
		resp.MatchedDate = &m
	}
	return resp
}

func listAlertEventsHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())

	limit := defaultAlertEventsLimit
	if l, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && l > 0 {
		limit = min(l, maxAlertEventsLimit)
	}
	rows, err := store.New(dbPool).ListAlertEventsByUser(r.Context(), store.ListAlertEventsByUserParams{
		UserID: user.ID, Limit: int32(limit),
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load alert events")
		return
	}
	out := make([]AlertEventResponse, 0, len(rows))
	for _, row := range rows {
		out = append(out, toAlertEventResponse(row))
	}
	writeJSON(w, http.StatusOK, out)
}

func markAlertEventsReadHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	if _, err := store.New(dbPool).MarkAlertEventsRead(r.Context(), user.ID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not mark events read")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func unreadAlertEventsCountHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	n, err := store.New(dbPool).CountUnreadAlertEvents(r.Context(), user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not count unread events")
		return
	}
	writeJSON(w, http.StatusOK, map[string]int64{"count": n})
}
