package main

import (
	"net/http"
	"time"

	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// Trip sharing: an owner mints an unguessable read-only link for a trip. The
// share binds to the trip's chat_id lineage (not one trips row) so the link
// always resolves to the latest version after agent refinements. Viewers need
// no account; a signed-in viewer can duplicate the trip into their own list.

type ShareResponse struct {
	Token     string    `json:"token"`
	Role      string    `json:"role"`
	CreatedAt time.Time `json:"created_at"`
}

type SharedTripResponse struct {
	Trip      TripResponse `json:"trip"`
	OwnerName string       `json:"owner_name"`
}

// shareChatID returns the trip's chat lineage id, assigning one to legacy
// (NULL chat_id) trips the same way refineTripHandler does.
func shareChatID(r *http.Request, trip store.Trip) (string, error) {
	if trip.ChatID != nil {
		return *trip.ChatID, nil
	}
	token, err := generateSessionToken()
	if err != nil {
		return "", err
	}
	newID := "chat-" + token
	updated, err := store.New(dbPool).UpdateTrip(r.Context(), store.UpdateTripParams{
		ChatID: &newID, ID: trip.ID, UserID: trip.UserID,
	})
	if err != nil {
		return "", err
	}
	return *updated.ChatID, nil
}

// createShareHandler mints (or returns the existing) viewer link for a trip.
// Idempotent per chat lineage: sharing twice reuses the same token.
func createShareHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	id, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	q := store.New(dbPool)
	trip, err := q.GetTripByIDAndOwner(r.Context(), store.GetTripByIDAndOwnerParams{ID: id, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	chatID, err := shareChatID(r, trip)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not create share link")
		return
	}
	if existing, err := q.GetActiveShareByOwnerAndChat(r.Context(), store.GetActiveShareByOwnerAndChatParams{
		OwnerID: user.ID, ChatID: chatID,
	}); err == nil {
		writeJSON(w, http.StatusOK, ShareResponse{Token: existing.Token, Role: existing.Role, CreatedAt: existing.CreatedAt})
		return
	}
	token, err := generateSessionToken()
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not create share link")
		return
	}
	share, err := q.CreateTripShare(r.Context(), store.CreateTripShareParams{
		ChatID: chatID, OwnerID: user.ID, Token: token, Role: "viewer",
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not create share link")
		return
	}
	writeJSON(w, http.StatusCreated, ShareResponse{Token: share.Token, Role: share.Role, CreatedAt: share.CreatedAt})
}

// revokeShareHandler revokes every active link for the trip's lineage.
func revokeShareHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	id, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	q := store.New(dbPool)
	trip, err := q.GetTripByIDAndOwner(r.Context(), store.GetTripByIDAndOwnerParams{ID: id, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	if trip.ChatID == nil {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if _, err := q.RevokeSharesByOwnerAndChat(r.Context(), store.RevokeSharesByOwnerAndChatParams{
		OwnerID: user.ID, ChatID: *trip.ChatID,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not revoke share link")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// resolveShare turns a token into (share, latest trip). Revoked/unknown
// tokens and empty lineages are all a plain 404 — no distinction leaks.
func resolveShare(r *http.Request) (store.TripShare, store.Trip, bool) {
	token := mux.Vars(r)["token"]
	q := store.New(dbPool)
	share, err := q.GetActiveShareByToken(r.Context(), token)
	if err != nil {
		return store.TripShare{}, store.Trip{}, false
	}
	trip, err := q.GetLatestTripByOwnerAndChat(r.Context(), store.GetLatestTripByOwnerAndChatParams{
		UserID: share.OwnerID, ChatID: &share.ChatID,
	})
	if err != nil {
		return store.TripShare{}, store.Trip{}, false
	}
	return share, trip, true
}

// sharedTripHandler is the public, unauthenticated read of a shared trip.
// Booking todos and all profile data are deliberately excluded; chat_id is
// stripped so the response carries nothing tied to the owner's sessions.
func sharedTripHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	share, trip, ok := resolveShare(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "shared trip not found")
		return
	}
	q := store.New(dbPool)
	items, err := q.GetItineraryItemsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	accommodations, err := q.ListAccommodationsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load stays")
		return
	}
	segments, err := q.ListSegmentsByTrip(r.Context(), trip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load segments")
		return
	}
	ownerName := "A traveler"
	if owner, err := q.GetUserByID(r.Context(), share.OwnerID); err == nil &&
		owner.DisplayName != nil && *owner.DisplayName != "" {
		ownerName = *owner.DisplayName
	}
	resp := toTripResponse(trip, items, accommodations, segments, nil)
	resp.ChatID = nil
	writeJSON(w, http.StatusOK, SharedTripResponse{Trip: resp, OwnerName: ownerName})
}

// duplicateSharedTripHandler copies the shared trip's latest version (items,
// stays, segments — attribution snapshots included, booking todos not) into a
// fresh draft lineage owned by the caller.
func duplicateSharedTripHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	_, src, ok := resolveShare(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "shared trip not found")
		return
	}
	ctx := r.Context()
	q := store.New(dbPool)
	items, err := q.GetItineraryItemsByTrip(ctx, src.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load itinerary")
		return
	}
	accommodations, err := q.ListAccommodationsByTrip(ctx, src.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load stays")
		return
	}
	segments, err := q.ListSegmentsByTrip(ctx, src.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load segments")
		return
	}

	chatToken, err := generateSessionToken()
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
		return
	}
	newChatID := "chat-" + chatToken

	tx, err := dbPool.Begin(ctx)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
		return
	}
	defer tx.Rollback(ctx)
	qtx := store.New(tx)

	copyTrip, err := qtx.CreateTrip(ctx, store.CreateTripParams{
		UserID:  user.ID,
		Title:   src.Title + " (copy)",
		Status:  "draft",
		ChatID:  &newChatID,
		Summary: src.Summary,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
		return
	}
	if src.StartDate.Valid || src.EndDate.Valid {
		if _, err := qtx.UpdateTrip(ctx, store.UpdateTripParams{
			StartDate: src.StartDate, EndDate: src.EndDate,
			ID: copyTrip.ID, UserID: user.ID,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
			return
		}
	}
	for _, it := range items {
		if _, err := qtx.CreateItineraryItem(ctx, store.CreateItineraryItemParams{
			TripID:                copyTrip.ID,
			Position:              it.Position,
			Name:                  it.Name,
			PlaceID:               it.PlaceID,
			Address:               it.Address,
			Latitude:              it.Latitude,
			Longitude:             it.Longitude,
			Category:              it.Category,
			TimeOfDay:             it.TimeOfDay,
			City:                  it.City,
			DayTripFrom:           it.DayTripFrom,
			Day:                   it.Day,
			LocalSourceName:       it.LocalSourceName,
			LocalRecommendationID: it.LocalRecommendationID,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
			return
		}
	}
	for _, a := range accommodations {
		if _, err := qtx.CreateAccommodation(ctx, store.CreateAccommodationParams{
			TripID: copyTrip.ID, Name: a.Name, Provider: a.Provider, Url: a.Url,
			Address: a.Address, Latitude: a.Latitude, Longitude: a.Longitude,
			CheckIn: a.CheckIn, CheckOut: a.CheckOut, PriceNote: a.PriceNote,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
			return
		}
	}
	for _, s := range segments {
		if _, err := qtx.CreateSegment(ctx, store.CreateSegmentParams{
			TripID: copyTrip.ID, Mode: s.Mode, Origin: s.Origin, Destination: s.Destination,
			DepartDate: s.DepartDate, ArriveDate: s.ArriveDate, Provider: s.Provider,
			Url: s.Url, PriceNote: s.PriceNote, Notes: s.Notes,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not copy trip")
		return
	}

	qr := store.New(dbPool)
	final, err := qr.GetTripByIDAndOwner(ctx, store.GetTripByIDAndOwnerParams{ID: copyTrip.ID, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load copied trip")
		return
	}
	copiedItems, err := qr.GetItineraryItemsByTrip(ctx, copyTrip.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load copied trip")
		return
	}
	writeJSON(w, http.StatusCreated, toTripResponse(final, copiedItems, nil, nil, nil))
}
