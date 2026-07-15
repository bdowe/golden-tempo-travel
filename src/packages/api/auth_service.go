package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/mail"
	"strings"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"travel-route-planner/store"
)

const sessionDuration = 30 * 24 * time.Hour // 30 days (see user-accounts spec)

func hashPassword(plain string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(plain), 12)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func checkPassword(hash, plain string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plain)) == nil
}

// hasPassword reports whether the account can authenticate with a password.
// SSO-only accounts (created via Google) have a nil hash until they set one
// through the password-reset flow.
func hasPassword(u store.User) bool {
	return u.PasswordHash != nil && *u.PasswordHash != ""
}

func checkUserPassword(u store.User, plain string) bool {
	return hasPassword(u) && checkPassword(*u.PasswordHash, plain)
}

// generateSessionToken returns a 64-char hex string from 32 random bytes.
func generateSessionToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func issueSession(ctx context.Context, q *store.Queries, userID uuid.UUID) (store.Session, error) {
	token, err := generateSessionToken()
	if err != nil {
		return store.Session{}, err
	}
	return q.CreateSession(ctx, store.CreateSessionParams{
		ID:        token,
		UserID:    userID,
		ExpiresAt: time.Now().Add(sessionDuration),
	})
}

func validateEmail(email string) bool {
	_, err := mail.ParseAddress(email)
	return err == nil
}

// defaultDisplayName uses the local part of the email when the user supplies none.
func defaultDisplayName(email string) string {
	if i := strings.Index(email, "@"); i > 0 {
		return email[:i]
	}
	return email
}
