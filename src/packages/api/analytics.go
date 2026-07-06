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

// Claude pricing used for the dashboard's COGS estimates (USD per million
// tokens), pinned to the model plan_handler.go actually calls. If the /plan
// model changes, update this block in the same commit. The resulting est_*
// fields cover Claude spend ONLY — Google Places (and other provider) calls
// are not metered yet (deferred, per specs/instrumentation-events).
const (
	planCostModelID              = "claude-sonnet-4-6"
	planCostInputUSDPerMTok      = 3.00
	planCostOutputUSDPerMTok     = 15.00
	planCostCacheWriteUSDPerMTok = 3.75 // 5-minute-TTL cache write (1.25x input)
	planCostCacheReadUSDPerMTok  = 0.30 // cache read (0.1x input)
)

// MetricsResponse is the Phase 1 dashboard-in-an-endpoint, keyed to the
// questions in docs/business-model.md §8 (activation, second-trip retention,
// attach rate, COGS per active user, cap-hit rate).
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
	// SecondTripRetention answers the business model's actual retention
	// question: users who created >= 2 trips at least 7 days apart in the
	// window (the Phase 3 "retention proven across >= 2 trips" trigger).
	SecondTripRetention int64 `json:"second_trip_retention"`
	// SessionFrequencyReturning is the old "returning users" number — plan
	// sessions on >= 2 distinct days. Kept as a session-frequency signal;
	// it is NOT trip retention (hence the rename from returning_users).
	SessionFrequencyReturning int64 `json:"session_frequency_returning"`
	// ActiveUsers is MAU within the window: distinct signed-in users with
	// >= 1 plan_session_started. The COGS-per-user denominator.
	ActiveUsers           int64 `json:"active_users"`
	PlanSessions          int64 `json:"plan_sessions"`
	PlanSessionsAnonymous int64 `json:"plan_sessions_anonymous"`
	// AgentLoopCapHits counts sessions whose agent loop hit the
	// max-iterations safety cap (metadata max_iterations_hit) — a
	// runaway-loop signal, not free-tier pressure. Formerly plan_cap_hits.
	AgentLoopCapHits      int64 `json:"agent_loop_cap_hits"`
	PlanInputTokens       int64 `json:"plan_input_tokens"`
	PlanOutputTokens      int64 `json:"plan_output_tokens"`
	PlanCacheReadTokens   int64 `json:"plan_cache_read_tokens"`
	PlanCacheCreateTokens int64 `json:"plan_cache_creation_tokens"`
	// EstClaudeCostUSD / EstCogsPerActiveUser are ESTIMATES covering Claude
	// spend only, from the planCost* pricing constants (Places calls are
	// not counted — deferred). EstCostModel names the model whose pricing
	// produced them, so the number is self-describing.
	EstCostModel         string  `json:"est_cost_model"`
	EstClaudeCostUSD     float64 `json:"est_claude_cost_usd"`
	EstCogsPerActiveUser float64 `json:"est_cogs_per_active_user"`
	AlertsCreated        int64   `json:"alerts_created"`
	AlertsTriggered      int64   `json:"alerts_triggered"`
	// FreeCapWouldHits / FreeCapUsersAffected are the §8 cap-hit rate — the
	// Phase-3 demand signal, keyed by cap_kind (plan_runs / active_trips).
	// Would-hits counts crossing events (only-on-crossing, so one per user
	// per crossing — see specs/free-cap-instrumentation); users-affected is
	// the distinct-user cohort, the primary trigger number. Nothing is
	// enforced anywhere — these are measurements of a cap that doesn't exist
	// in code yet.
	FreeCapWouldHits     map[string]int64 `json:"free_cap_would_hits"`
	FreeCapUsersAffected map[string]int64 `json:"free_cap_users_affected"`
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

	// One GROUP BY round trip replaces the previous per-type count queries.
	counts := map[string]int64{}
	if rows, err := q.CountEventsByTypeGrouped(ctx, since); err == nil {
		for _, row := range rows {
			counts[row.EventType] = row.N
		}
	} else {
		log.Printf("metrics: grouped counts: %v", err)
	}

	resp := MetricsResponse{
		Days:                 days,
		Signups:              counts["user_registered"],
		OnboardingsCompleted: counts["onboarding_completed"],
		TripsCreated:         counts["trip_created"],
		TripsRefined:         counts["trip_refined"],
		BookingClicks:        counts["booking_link_clicked"],
		TodosMarkedBooked:    counts["booking_marked_booked"],
		AlertsCreated:        counts["alert_created"],
		AlertsTriggered:      counts["alert_triggered"],
		ClicksByProvider:     map[string]int64{},
		FreeCapWouldHits:     map[string]int64{},
		FreeCapUsersAffected: map[string]int64{},
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
		resp.PlanSessionsAnonymous = totals.AnonymousSessions
		resp.AgentLoopCapHits = totals.AgentLoopCapHits
		resp.PlanInputTokens = totals.InputTokens
		resp.PlanOutputTokens = totals.OutputTokens
		resp.PlanCacheReadTokens = totals.CacheReadTokens
		resp.PlanCacheCreateTokens = totals.CacheCreationTokens
	}
	if rows, err := q.FreeCapWouldHitCounts(ctx, since); err == nil {
		for _, row := range rows {
			resp.FreeCapWouldHits[row.CapKind] = row.WouldHits
			resp.FreeCapUsersAffected[row.CapKind] = row.UsersAffected
		}
	}
	if eng, err := q.UserEngagementCounts(ctx, since); err == nil {
		resp.ActiveUsers = eng.ActiveUsers
		resp.SessionFrequencyReturning = eng.SessionFrequencyReturning
		resp.SecondTripRetention = eng.SecondTripRetention
	}
	// Estimated Claude spend for the window (Claude only; Places not
	// counted). input_tokens is the uncached remainder — cache reads and
	// writes are billed separately at their own rates.
	resp.EstCostModel = planCostModelID
	resp.EstClaudeCostUSD = (float64(resp.PlanInputTokens)*planCostInputUSDPerMTok +
		float64(resp.PlanOutputTokens)*planCostOutputUSDPerMTok +
		float64(resp.PlanCacheCreateTokens)*planCostCacheWriteUSDPerMTok +
		float64(resp.PlanCacheReadTokens)*planCostCacheReadUSDPerMTok) / 1e6
	if resp.ActiveUsers > 0 {
		resp.EstCogsPerActiveUser = resp.EstClaudeCostUSD / float64(resp.ActiveUsers)
	}
	writeJSON(w, http.StatusOK, resp)
}
