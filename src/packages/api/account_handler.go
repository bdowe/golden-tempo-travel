package main

import (
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"unicode/utf8"

	"travel-route-planner/store"
)

// Account self-service: display name, password change, session revocation,
// deletion. All behind authMiddleware; the destructive/credential routes sit
// on the strict rate tier and re-verify the password (a stolen session must
// not be enough to take over or destroy the account).

func patchAccountHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	var req struct {
		DisplayName *string `json:"display_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if req.DisplayName == nil {
		writeJSONError(w, http.StatusBadRequest, "nothing to update")
		return
	}
	name := strings.TrimSpace(*req.DisplayName)
	if name == "" || utf8.RuneCountInString(name) > 60 {
		writeJSONError(w, http.StatusUnprocessableEntity, "display_name must be 1-60 characters")
		return
	}
	updated, err := store.New(dbPool).UpdateUserDisplayName(r.Context(), store.UpdateUserDisplayNameParams{
		ID: user.ID, DisplayName: &name,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not update account")
		return
	}
	writeJSON(w, http.StatusOK, toUserResponse(updated))
}

func changePasswordHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	var req struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if !checkPassword(user.PasswordHash, req.CurrentPassword) {
		writeJSONError(w, http.StatusUnauthorized, "current password is incorrect")
		return
	}
	if len(req.NewPassword) < 8 {
		writeJSONError(w, http.StatusUnprocessableEntity, "password must be at least 8 characters")
		return
	}
	hash, err := hashPassword(req.NewPassword)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not secure password")
		return
	}
	q := store.New(dbPool)
	if err := q.UpdateUserPassword(r.Context(), store.UpdateUserPasswordParams{ID: user.ID, PasswordHash: hash}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not update password")
		return
	}
	// Same policy as password reset: every existing session dies with the old
	// password; a fresh one keeps this device signed in.
	if err := q.DeleteSessionsByUser(r.Context(), user.ID); err != nil {
		log.Printf("change password: could not revoke sessions for %s: %v", user.ID, err)
	}
	session, err := issueSession(r.Context(), q, user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "password changed — sign in again")
		return
	}
	writeJSON(w, http.StatusOK, AuthResponse{User: toUserResponse(user), Token: session.ID})
}

func logoutAllHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	if err := store.New(dbPool).DeleteSessionsByUser(r.Context(), user.ID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not sign out other devices")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func deleteAccountHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	user, _ := userFromContext(r.Context())
	var req struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if !checkPassword(user.PasswordHash, req.Password) {
		writeJSONError(w, http.StatusUnauthorized, "password is incorrect")
		return
	}
	// Every user-owned table cascades off users(id); analytics_events keeps
	// its (PII-free) rows by design — the event log is append-only.
	n, err := store.New(dbPool).DeleteUser(r.Context(), user.ID)
	if err != nil || n == 0 {
		writeJSONError(w, http.StatusInternalServerError, "could not delete account")
		return
	}
	log.Printf("account deleted: %s", user.ID)
	w.WriteHeader(http.StatusNoContent)
}
