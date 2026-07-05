package main

import (
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// Collaborative editing membership. A signed-in user redeems an editor-role
// share token to become a collaborator on the trip's lineage; the token is
// only the capability to join — membership is explicit state the owner can
// list and revoke per person. Revoking share links stops new joins but does
// not evict existing collaborators.

type JoinSharedTripResponse struct {
	TripID string `json:"trip_id"`
	Access string `json:"access"`
}

type CollaboratorResponse struct {
	UserID      string    `json:"user_id"`
	DisplayName string    `json:"display_name"`
	Email       string    `json:"email"`
	JoinedAt    time.Time `json:"joined_at"`
}

// editableTrip resolves {id} and confirms the caller may edit the trip:
// owner, or active editor-collaborator on the trip's lineage. Returns the
// trip row — call sites need trip.UserID (the owner) for follow-up reads,
// not the caller's id. Non-members get the same 404 as before.
func editableTrip(w http.ResponseWriter, r *http.Request) (store.Trip, bool) {
	user, _ := userFromContext(r.Context())
	tripID, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return store.Trip{}, false
	}
	trip, err := store.New(dbPool).GetEditableTripByID(r.Context(),
		store.GetEditableTripByIDParams{ID: tripID, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return store.Trip{}, false
	}
	return trip, true
}

// joinSharedTripHandler redeems an editor-role token for membership.
// Idempotent; the owner joining their own trip is a no-op success.
func joinSharedTripHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	share, trip, ok := resolveShare(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "shared trip not found")
		return
	}
	if share.Role != "editor" {
		writeJSONError(w, http.StatusForbidden, "this link doesn't allow editing")
		return
	}
	if trip.UserID != user.ID {
		if err := store.New(dbPool).CreateTripCollaborator(r.Context(), store.CreateTripCollaboratorParams{
			ChatID: share.ChatID, OwnerID: share.OwnerID, UserID: user.ID,
		}); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not join trip")
			return
		}
		go recordEvent(user.ID, "collaborator_joined", &trip.ID, map[string]any{
			"owner_id": share.OwnerID.String(),
		})
	}
	access := "editor"
	if trip.UserID == user.ID {
		access = "owner"
	}
	writeJSON(w, http.StatusOK, JoinSharedTripResponse{TripID: trip.ID.String(), Access: access})
}

// listCollaboratorsHandler is owner-only.
func listCollaboratorsHandler(w http.ResponseWriter, r *http.Request) {
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
	out := make([]CollaboratorResponse, 0)
	if trip.ChatID != nil {
		rows, err := q.ListCollaboratorsByOwnerAndChat(r.Context(), store.ListCollaboratorsByOwnerAndChatParams{
			OwnerID: user.ID, ChatID: *trip.ChatID,
		})
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "could not load co-planners")
			return
		}
		for _, c := range rows {
			out = append(out, CollaboratorResponse{
				UserID:      c.UserID.String(),
				DisplayName: c.DisplayName,
				Email:       c.Email,
				JoinedAt:    c.CreatedAt,
			})
		}
	}
	writeJSON(w, http.StatusOK, out)
}

// removeCollaboratorHandler is owner-only; soft-revokes one membership.
func removeCollaboratorHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	id, ok := tripIDFromPath(r)
	if !ok {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	collabID, err := uuid.Parse(mux.Vars(r)["userId"])
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "co-planner not found")
		return
	}
	q := store.New(dbPool)
	trip, err := q.GetTripByIDAndOwner(r.Context(), store.GetTripByIDAndOwnerParams{ID: id, UserID: user.ID})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "trip not found")
		return
	}
	if trip.ChatID == nil {
		writeJSONError(w, http.StatusNotFound, "co-planner not found")
		return
	}
	n, err := q.RevokeTripCollaborator(r.Context(), store.RevokeTripCollaboratorParams{
		OwnerID: user.ID, ChatID: *trip.ChatID, UserID: collabID,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not remove co-planner")
		return
	}
	if n == 0 {
		writeJSONError(w, http.StatusNotFound, "co-planner not found")
		return
	}
	go recordEvent(user.ID, "collaborator_removed", &trip.ID, map[string]any{
		"collaborator_id": collabID.String(),
	})
	w.WriteHeader(http.StatusNoContent)
}

// listSharedWithMeHandler returns the latest version of every lineage the
// caller collaborates on, with owner attribution.
func listSharedWithMeHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	rows, err := store.New(dbPool).ListLatestCollaboratedTripsForUser(r.Context(), user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not load shared trips")
		return
	}
	out := make([]TripResponse, 0, len(rows))
	for _, t := range rows {
		resp := toTripResponse(store.Trip{
			ID: t.ID, UserID: t.UserID, CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt,
			Title: t.Title, StartDate: t.StartDate, EndDate: t.EndDate,
			Status: t.Status, ChatID: t.ChatID,
		}, nil, nil, nil, nil)
		resp.VersionCount = int(t.VersionCount)
		resp.Cities = t.Cities
		resp.Access = "editor"
		if t.OwnerName != "" {
			name := t.OwnerName
			resp.OwnerName = &name
		}
		out = append(out, resp)
	}
	writeJSON(w, http.StatusOK, out)
}
