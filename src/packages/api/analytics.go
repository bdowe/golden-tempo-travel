package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// First-party analytics (specs/instrumentation-events): a lightweight event
// log for the growth-phase funnel numbers — activation, retention, booking
// attach rate, AI cost per user. Recording is strictly best-effort: with the
// database down every instrumented flow behaves exactly as before and events
// are silently dropped. No PII beyond the user id.

// clientEventTypes are the only types POST /events accepts — server-side
// types cannot be spoofed through the client endpoint.
var clientEventTypes = map[string]bool{
	"booking_link_clicked": true,
}

// maxEventMetadataBytes caps the metadata bag (small, flat detail only).
const maxEventMetadataBytes = 2048

// recordEvent writes one analytics event. Fire-and-forget semantics: errors
// are logged, never returned — callers must not branch on instrumentation.
func recordEvent(userID uuid.UUID, eventType string, tripID *uuid.UUID, metadata map[string]any) {
	recordEventOpt(&userID, eventType, tripID, metadata)
}

// recordEventOpt is recordEvent for flows where the caller may be anonymous
// (nil userID), e.g. the public /plan endpoint. Uses its own timeout off
// context.Background() so recording survives handler teardown (several call
// sites are goroutines or post-stream code).
func recordEventOpt(userID *uuid.UUID, eventType string, tripID *uuid.UUID, metadata map[string]any) {
	if dbPool == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var meta []byte
	if len(metadata) > 0 {
		b, err := json.Marshal(metadata)
		if err != nil || len(b) > maxEventMetadataBytes {
			log.Printf("analytics: dropping oversized/unencodable metadata for %s", eventType)
		} else {
			meta = b
		}
	}
	var tid pgtype.UUID
	if tripID != nil {
		tid = pgtype.UUID{Bytes: *tripID, Valid: true}
	}
	var uidParam pgtype.UUID
	if userID != nil {
		uidParam = pgtype.UUID{Bytes: *userID, Valid: true}
	}
	if err := store.New(dbPool).CreateAnalyticsEvent(ctx, store.CreateAnalyticsEventParams{
		UserID:    uidParam,
		EventType: eventType,
		TripID:    tid,
		Metadata:  meta,
	}); err != nil {
		log.Printf("analytics: could not record %s: %v", eventType, err)
	}
}

// recordClientEventHandler is POST /api/v1/events — the one client-observed
// moment (opening a booking link). Always 202 once the payload is valid, even
// when persistence is degraded: tracking must never surface as a user error.
func recordClientEventHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	var req struct {
		EventType string         `json:"event_type"`
		TripID    *string        `json:"trip_id"`
		Metadata  map[string]any `json:"metadata"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if !clientEventTypes[req.EventType] {
		writeJSONError(w, http.StatusBadRequest, "event_type is missing or not permitted")
		return
	}
	var tripID *uuid.UUID
	if req.TripID != nil {
		if tid, err := uuid.Parse(*req.TripID); err == nil {
			tripID = &tid
		}
	}
	go recordEvent(user.ID, req.EventType, tripID, req.Metadata)
	w.WriteHeader(http.StatusAccepted)
}

// MetricsResponse is the Phase 1 dashboard-in-an-endpoint.
type MetricsResponse struct {
	Days                  int              `json:"days"`
	Signups               int64            `json:"signups"`
	ActivatedSignups      int64            `json:"activated_signups"`
	ActivationRate        float64          `json:"activation_rate"`
	OnboardingsCompleted  int64            `json:"onboardings_completed"`
	TripsCreated          int64            `json:"trips_created"`
	TripsRefined          int64            `json:"trips_refined"`
	TripsWithBookingClick int64            `json:"trips_with_booking_click"`
	AttachRate            float64          `json:"attach_rate"`
	BookingClicks         int64            `json:"booking_clicks"`
	ClicksByProvider      map[string]int64 `json:"clicks_by_provider"`
	TodosMarkedBooked     int64            `json:"todos_marked_booked"`
	ReturningUsers        int64            `json:"returning_users"`
	PlanSessions          int64            `json:"plan_sessions"`
	PlanSessionsAnonymous int64            `json:"plan_sessions_anonymous"`
	PlanCapHits           int64            `json:"plan_cap_hits"`
	PlanInputTokens       int64            `json:"plan_input_tokens"`
	PlanOutputTokens      int64            `json:"plan_output_tokens"`
	PlanCacheReadTokens   int64            `json:"plan_cache_read_tokens"`
	PlanCacheCreateTokens int64            `json:"plan_cache_creation_tokens"`
	AlertsCreated         int64            `json:"alerts_created"`
	AlertsTriggered       int64            `json:"alerts_triggered"`
}

// adminMetricsHandler is GET /api/v1/admin/metrics?days= (admin only; gated
// at route registration).
func adminMetricsHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	days := 30
	if d, err := strconv.Atoi(r.URL.Query().Get("days")); err == nil && d > 0 && d <= 3650 {
		days = d
	}
	since := time.Now().AddDate(0, 0, -days)
	ctx := r.Context()
	q := store.New(dbPool)

	count := func(eventType string) int64 {
		n, err := q.CountEventsByType(ctx, store.CountEventsByTypeParams{
			EventType: eventType, CreatedAt: since,
		})
		if err != nil {
			log.Printf("metrics: count %s: %v", eventType, err)
		}
		return n
	}

	resp := MetricsResponse{
		Days:                 days,
		Signups:              count("user_registered"),
		OnboardingsCompleted: count("onboarding_completed"),
		TripsCreated:         count("trip_created"),
		TripsRefined:         count("trip_refined"),
		BookingClicks:        count("booking_link_clicked"),
		TodosMarkedBooked:    count("booking_marked_booked"),
		AlertsCreated:        count("alert_created"),
		AlertsTriggered:      count("alert_triggered"),
		ClicksByProvider:     map[string]int64{},
	}
	if n, err := q.CountActivatedSignups(ctx, since); err == nil {
		resp.ActivatedSignups = n
	}
	if resp.Signups > 0 {
		resp.ActivationRate = float64(resp.ActivatedSignups) / float64(resp.Signups)
	}
	if n, err := q.CountTripsWithBookingClick(ctx, since); err == nil {
		resp.TripsWithBookingClick = n
	}
	if resp.TripsCreated > 0 {
		resp.AttachRate = float64(resp.TripsWithBookingClick) / float64(resp.TripsCreated)
	}
	if rows, err := q.BookingClicksByProvider(ctx, since); err == nil {
		for _, row := range rows {
			resp.ClicksByProvider[row.Provider] = row.Clicks
		}
	}
	if totals, err := q.PlanSessionTotals(ctx, since); err == nil {
		resp.PlanSessions = totals.Sessions
		resp.PlanInputTokens = totals.InputTokens
		resp.PlanOutputTokens = totals.OutputTokens
		resp.PlanCacheReadTokens = totals.CacheReadTokens
		resp.PlanCacheCreateTokens = totals.CacheCreationTokens
	}
	if n, err := q.CountAnonymousPlanSessions(ctx, since); err == nil {
		resp.PlanSessionsAnonymous = n
	}
	if n, err := q.CountPlanCapHits(ctx, since); err == nil {
		resp.PlanCapHits = n
	}
	if n, err := q.CountReturningUsers(ctx, since); err == nil {
		resp.ReturningUsers = n
	}
	writeJSON(w, http.StatusOK, resp)
}
