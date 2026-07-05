package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"travel-route-planner/store"
)

// --- request / response types ---

type RegisterRequest struct {
	Email       string  `json:"email"`
	Password    string  `json:"password"`
	DisplayName *string `json:"display_name"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type UserResponse struct {
	ID              string    `json:"id"`
	Email           string    `json:"email"`
	DisplayName     string    `json:"display_name"`
	IsAdmin         bool      `json:"is_admin"`
	NeedsOnboarding bool      `json:"needs_onboarding"`
	CreatedAt       time.Time `json:"created_at"`
}

type AuthResponse struct {
	User  UserResponse `json:"user"`
	Token string       `json:"token"`
}

func toUserResponse(u store.User) UserResponse {
	name := ""
	if u.DisplayName != nil {
		name = *u.DisplayName
	}
	return UserResponse{
		ID:              u.ID.String(),
		Email:           u.Email,
		DisplayName:     name,
		IsAdmin:         u.IsAdmin,
		NeedsOnboarding: !u.OnboardedAt.Valid,
		CreatedAt:       u.CreatedAt,
	}
}

// --- small response helpers ---

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func writeJSONError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, Response{Message: msg, Status: "error"})
}

// --- auth context + middleware ---

type contextKey string

const userContextKey contextKey = "user"

func bearerToken(r *http.Request) string {
	const prefix = "Bearer "
	h := r.Header.Get("Authorization")
	if strings.HasPrefix(h, prefix) {
		return strings.TrimSpace(h[len(prefix):])
	}
	return ""
}

func userFromContext(ctx context.Context) (store.User, bool) {
	u, ok := ctx.Value(userContextKey).(store.User)
	return u, ok
}

// userIDFromRequest resolves the bearer token to a user ID without failing the
// request when absent/invalid. Used by endpoints that are open to anonymous
// callers but persist data only when signed in (e.g. /plan).
func userIDFromRequest(r *http.Request) (uuid.UUID, bool) {
	if dbPool == nil {
		return uuid.UUID{}, false
	}
	token := bearerToken(r)
	if token == "" {
		return uuid.UUID{}, false
	}
	row, err := store.New(dbPool).GetSessionWithUser(r.Context(), token)
	if err != nil || row.Session.ExpiresAt.Before(time.Now()) {
		return uuid.UUID{}, false
	}
	return row.User.ID, true
}

// authMiddleware resolves the bearer token to a user and rejects unauthenticated
// requests with 401. Wrap only the routes that require authentication.
func authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if dbPool == nil {
			writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
			return
		}
		token := bearerToken(r)
		if token == "" {
			writeJSONError(w, http.StatusUnauthorized, "authentication required")
			return
		}
		q := store.New(dbPool)
		row, err := q.GetSessionWithUser(r.Context(), token)
		if err != nil || row.Session.ExpiresAt.Before(time.Now()) {
			writeJSONError(w, http.StatusUnauthorized, "invalid or expired session")
			return
		}
		_ = q.DeleteExpiredSessions(r.Context()) // opportunistic cleanup
		ctx := context.WithValue(r.Context(), userContextKey, row.User)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// adminMiddleware runs after authMiddleware's token→user resolution and rejects
// non-admin users with 403. Wrap admin-only routes as
// authMiddleware(adminMiddleware(handler)).
func adminMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, ok := userFromContext(r.Context())
		if !ok {
			writeJSONError(w, http.StatusUnauthorized, "authentication required")
			return
		}
		if !user.IsAdmin {
			writeJSONError(w, http.StatusForbidden, "admin access required")
			return
		}
		next.ServeHTTP(w, r.WithContext(r.Context()))
	})
}

// --- handlers ---

func registerHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if !validateEmail(req.Email) {
		writeJSONError(w, http.StatusUnprocessableEntity, "a valid email address is required")
		return
	}
	if len(req.Password) < 8 {
		writeJSONError(w, http.StatusUnprocessableEntity, "password must be at least 8 characters")
		return
	}

	q := store.New(dbPool)
	if _, err := q.GetUserByEmail(r.Context(), req.Email); err == nil {
		writeJSONError(w, http.StatusConflict, "an account with this email already exists")
		return
	} else if !errors.Is(err, pgx.ErrNoRows) {
		writeJSONError(w, http.StatusInternalServerError, "could not check email")
		return
	}

	hash, err := hashPassword(req.Password)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not secure password")
		return
	}

	displayName := req.DisplayName
	if displayName == nil || strings.TrimSpace(*displayName) == "" {
		d := defaultDisplayName(req.Email)
		displayName = &d
	}

	user, err := q.CreateUser(r.Context(), store.CreateUserParams{
		Email:        req.Email,
		PasswordHash: hash,
		DisplayName:  displayName,
	})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not create account")
		return
	}

	session, err := issueSession(r.Context(), q, user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not start session")
		return
	}
	writeJSON(w, http.StatusCreated, AuthResponse{User: toUserResponse(user), Token: session.ID})
}

func loginHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	req.Email = strings.ToLower(strings.TrimSpace(req.Email))
	if req.Email == "" || req.Password == "" {
		writeJSONError(w, http.StatusUnprocessableEntity, "email and password are required")
		return
	}

	q := store.New(dbPool)
	user, err := q.GetUserByEmail(r.Context(), req.Email)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && !checkPassword(user.PasswordHash, req.Password)) {
		// Generic message — never reveal whether the email or the password was wrong.
		writeJSONError(w, http.StatusUnauthorized, "invalid email or password")
		return
	}
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not look up account")
		return
	}

	session, err := issueSession(r.Context(), q, user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not start session")
		return
	}
	writeJSON(w, http.StatusOK, AuthResponse{User: toUserResponse(user), Token: session.ID})
}

func logoutHandler(w http.ResponseWriter, r *http.Request) {
	if token := bearerToken(r); token != "" && dbPool != nil {
		_ = store.New(dbPool).DeleteSession(r.Context(), token)
	}
	w.WriteHeader(http.StatusNoContent)
}

func meHandler(w http.ResponseWriter, r *http.Request) {
	user, ok := userFromContext(r.Context())
	if !ok {
		writeJSONError(w, http.StatusUnauthorized, "not authenticated")
		return
	}
	writeJSON(w, http.StatusOK, toUserResponse(user))
}

// completeOnboardingHandler marks the signup quiz as done (or skipped).
// Idempotent: repeat calls keep the original onboarded_at.
func completeOnboardingHandler(w http.ResponseWriter, r *http.Request) {
	user, ok := userFromContext(r.Context())
	if !ok {
		writeJSONError(w, http.StatusUnauthorized, "not authenticated")
		return
	}
	updated, err := store.New(dbPool).MarkUserOnboarded(r.Context(), user.ID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not complete onboarding")
		return
	}
	writeJSON(w, http.StatusOK, toUserResponse(updated))
}
