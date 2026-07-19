package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"travel-route-planner/store"
)

// Email verification + password reset. Tokens are single-use, sha256-hashed
// at rest (they transit email, unlike session tokens), and short-lived:
const (
	resetTokenTTL  = 1 * time.Hour
	verifyTokenTTL = 24 * time.Hour
)

func hashEmailToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// issueEmailToken voids older tokens for the purpose and stores a fresh one,
// returning the plaintext token for the email body.
func issueEmailToken(ctx context.Context, q *store.Queries, user store.User, purpose string, ttl time.Duration) (string, error) {
	token, err := generateSessionToken()
	if err != nil {
		return "", err
	}
	if err := q.InvalidateEmailTokens(ctx, store.InvalidateEmailTokensParams{
		UserID: user.ID, Purpose: purpose,
	}); err != nil {
		return "", err
	}
	if _, err := q.CreateEmailToken(ctx, store.CreateEmailTokenParams{
		UserID:    user.ID,
		Purpose:   purpose,
		TokenHash: hashEmailToken(token),
		ExpiresAt: time.Now().Add(ttl),
	}); err != nil {
		return "", err
	}
	return token, nil
}

// publicBaseURL is where the app is reachable from a user's browser, for
// links in emails. Defaults to the local gateway.
func publicBaseURL() string {
	if u := strings.TrimRight(os.Getenv("PUBLIC_BASE_URL"), "/"); u != "" {
		return u
	}
	return "http://localhost:3000"
}

// publicAppPath is the path prefix under which the Flutter app is served
// (env PUBLIC_APP_PATH; "/" by default, e.g. "/app/" in deployment).
// Normalized to always start and end with "/".
func publicAppPath() string {
	p := strings.TrimSpace(os.Getenv("PUBLIC_APP_PATH"))
	if p == "" {
		return "/"
	}
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	if !strings.HasSuffix(p, "/") {
		p += "/"
	}
	return p
}

// publicAppURL builds a user-facing app deep link, e.g.
// publicAppURL("reset/", token) => https://host/reset/<token>.
func publicAppURL(parts ...string) string {
	return publicBaseURL() + publicAppPath() + strings.Join(parts, "")
}

// sendVerificationEmail is called fire-and-forget after registration (same
// pattern as the profile distiller kickoff) and from the resend endpoint.
func sendVerificationEmail(user store.User) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	q := store.New(dbPool)
	token, err := issueEmailToken(ctx, q, user, "verify", verifyTokenTTL)
	if err != nil {
		log.Printf("verification email: could not issue token for %s: %v", user.Email, err)
		return
	}
	link := publicAppURL("verify/", token)
	body := "Welcome to Golden Tempo Travel!\n\n" +
		"Confirm your email address by opening this link:\n\n" + link + "\n\n" +
		"The link expires in 24 hours. If you didn't create an account, you can ignore this email."
	if err := emailService.Send(user.Email, "Confirm your email — Golden Tempo Travel", body); err != nil {
		log.Printf("verification email: send to %s failed: %v", user.Email, err)
	}
}

// requestVerificationHandler re-sends the verify mail for the signed-in user.
func requestVerificationHandler(w http.ResponseWriter, r *http.Request) {
	user, _ := userFromContext(r.Context())
	if user.EmailVerifiedAt.Valid {
		writeJSON(w, http.StatusOK, map[string]string{"status": "already verified"})
		return
	}
	safeGo("sendVerificationEmail", func() { sendVerificationEmail(user) })
	w.WriteHeader(http.StatusAccepted)
}

// verifyEmailHandler accepts the token via POST JSON (programmatic) or GET
// query (the link in the email, answered with a tiny HTML page so it works
// without the app).
func verifyEmailHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var token string
	if r.Method == http.MethodGet {
		token = r.URL.Query().Get("token")
	} else {
		var req struct {
			Token string `json:"token"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSONError(w, http.StatusBadRequest, "invalid JSON")
			return
		}
		token = req.Token
	}
	token = strings.TrimSpace(token)
	if token == "" {
		writeJSONError(w, http.StatusBadRequest, "token is required")
		return
	}

	q := store.New(dbPool)
	et, err := q.GetValidEmailToken(r.Context(), store.GetValidEmailTokenParams{
		TokenHash: hashEmailToken(token), Purpose: "verify",
	})
	if err != nil {
		if r.Method == http.MethodGet {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.WriteHeader(http.StatusNotFound)
			fmt.Fprint(w, "<html><body><h2>Link expired or already used</h2><p>Request a new verification email from your account.</p></body></html>")
			return
		}
		writeJSONError(w, http.StatusNotFound, "invalid or expired token")
		return
	}
	if err := q.MarkEmailTokenUsed(r.Context(), et.ID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not verify email")
		return
	}
	if err := q.MarkUserEmailVerified(r.Context(), et.UserID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not verify email")
		return
	}
	if r.Method == http.MethodGet {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w, "<html><body><h2>Email verified ✓</h2><p>You're all set — head back to <a href=%q>Golden Tempo Travel</a>.</p></body></html>", publicBaseURL())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "verified"})
}

// requestPasswordResetHandler always answers 202 — whether or not the email
// has an account — so it can't be used to enumerate users.
func requestPasswordResetHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var req struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	email := strings.ToLower(strings.TrimSpace(req.Email))
	if email == "" {
		writeJSONError(w, http.StatusBadRequest, "email is required")
		return
	}

	q := store.New(dbPool)
	user, err := q.GetUserByEmail(r.Context(), email)
	if err == nil {
		u := user
		safeGo("sendPasswordResetEmail", func() {
			ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
			defer cancel()
			token, err := issueEmailToken(ctx, store.New(dbPool), u, "reset", resetTokenTTL)
			if err != nil {
				log.Printf("password reset: could not issue token for %s: %v", u.Email, err)
				return
			}
			body := "Someone (hopefully you) asked to reset your Golden Tempo Travel password.\n\n" +
				"Reset your password: " + publicAppURL("reset/", token) + "\n\n" +
				"If the link doesn't open, use this reset code instead:\n\n    " + token + "\n\n" +
				"In the app, choose \"Forgot password?\", paste the code, and pick a new password. " +
				"The link and code are valid for 1 hour and work once. If this wasn't you, ignore this email — your password is unchanged."
			if err := emailService.Send(u.Email, "Reset your password — Golden Tempo Travel", body); err != nil {
				log.Printf("password reset: send to %s failed: %v", u.Email, err)
			}
		})
	} else if !errors.Is(err, pgx.ErrNoRows) {
		log.Printf("password reset: lookup failed for %s: %v", email, err)
	}
	w.WriteHeader(http.StatusAccepted)
}

// resetPasswordHandler consumes a reset token, sets the new password, and
// kills every session for the user.
func resetPasswordHandler(w http.ResponseWriter, r *http.Request) {
	if dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "database unavailable")
		return
	}
	var req struct {
		Token       string `json:"token"`
		NewPassword string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if strings.TrimSpace(req.Token) == "" {
		writeJSONError(w, http.StatusBadRequest, "token is required")
		return
	}
	if len(req.NewPassword) < 8 {
		writeJSONError(w, http.StatusUnprocessableEntity, "password must be at least 8 characters")
		return
	}

	q := store.New(dbPool)
	et, err := q.GetValidEmailToken(r.Context(), store.GetValidEmailTokenParams{
		TokenHash: hashEmailToken(strings.TrimSpace(req.Token)), Purpose: "reset",
	})
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "invalid or expired reset code")
		return
	}
	hash, err := hashPassword(req.NewPassword)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not secure password")
		return
	}
	if err := q.MarkEmailTokenUsed(r.Context(), et.ID); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not reset password")
		return
	}
	if err := q.UpdateUserPassword(r.Context(), store.UpdateUserPasswordParams{
		ID: et.UserID, PasswordHash: &hash,
	}); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not reset password")
		return
	}
	if err := q.DeleteSessionsByUser(r.Context(), et.UserID); err != nil {
		log.Printf("password reset: could not clear sessions for %s: %v", et.UserID, err)
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "password updated"})
}
