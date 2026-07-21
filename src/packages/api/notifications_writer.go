package main

import (
	"context"
	"encoding/json"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"

	"travel-route-planner/store"
)

// Notification writers (Wave 16). The read/mark API lives in
// notifications_handler.go; this file only produces rows. Every writer is
// best-effort and fire-and-forget from its call site (`go notify...`): a
// failed or slow notification must never block or fail the edit that triggered
// it. Each uses its own timeout off context.Background() so it survives the
// originating request's teardown, mirroring recordEventOpt.

// notifyCollabEdit records "a collaborator edited a shared trip" for everyone
// on the trip except the actor. It is intentionally SELF-GATED in SQL
// (InsertCollabEditNotifications): the query no-ops when the actor is the trip
// owner or the trip has no other members, and throttles to one row per
// recipient per (trip, actor) per 6h window — so it is safe (and cheap: one
// indexed write) to call unconditionally on every content edit. Call it
// wherever a TouchTrip-style content mutation happens with a known actor.
func notifyCollabEdit(tripID, actorUserID uuid.UUID) {
	if dbPool == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := store.New(dbPool).InsertCollabEditNotifications(ctx, store.InsertCollabEditNotificationsParams{
		ActorID: actorUserID,
		TripID:  tripID,
	}); err != nil {
		log.Printf("notifications: collab_edit for trip %s failed: %v", tripID, err)
	}
}

// notifyInviteAccepted tells a trip owner that someone redeemed their invite.
// One-time event (accept is single-use), so no throttle. accepterName falls
// back to a generic label when the redeemer has no display name, matching the
// invite email's "A traveler" posture.
func notifyInviteAccepted(ownerID uuid.UUID, accepter store.User, trip store.Trip) {
	if dbPool == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// There is no request here, and the row is read by the OWNER — so the
	// fallback label is written in the owner's stored locale, not the
	// accepter's. Only this one value is display text; "accepter_name" and
	// "trip_title" are payload keys the client renders around, and trip.Title
	// is traveler data.
	locale := defaultLocale
	if owner, err := store.New(dbPool).GetUserByID(ctx, ownerID); err == nil {
		locale = localeOrDefault(owner.Locale)
	}
	name := tr(locale, "notif.aTraveler")
	if accepter.DisplayName != nil && *accepter.DisplayName != "" {
		name = *accepter.DisplayName
	}
	payload, err := json.Marshal(map[string]string{
		"accepter_name": name,
		"trip_title":    trip.Title,
	})
	if err != nil {
		return
	}
	if _, err := store.New(dbPool).InsertNotification(ctx, store.InsertNotificationParams{
		UserID:  ownerID,
		Type:    "invite_accepted",
		Payload: payload,
		TripID:  pgtype.UUID{Bytes: trip.ID, Valid: true},
	}); err != nil {
		log.Printf("notifications: invite_accepted for owner %s failed: %v", ownerID, err)
	}
}
