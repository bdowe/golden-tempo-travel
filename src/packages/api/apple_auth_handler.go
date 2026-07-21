package main

import (
	"errors"
	"net/http"
	"net/url"
	"strings"

	"github.com/jackc/pgx/v5"

	"travel-route-planner/store"
)

// Sign in with Apple (specs/apple-sso), the sibling of google_auth_handler.go.
// Same browser flow and /sso/<code> handoff, with three Apple deltas:
//
//   - the callback is a cross-site POST (`response_mode=form_post` is required
//     when requesting the name/email scopes), so the state cookie must be
//     SameSite=None; Secure — Lax cookies don't ride cross-site POSTs. Secure
//     is unconditional: Apple rejects http/localhost return URLs, so a local
//     browser flow is impossible either way (tests drive the router directly).
//   - no PKCE (Apple doesn't support it); CSRF protection is the state cookie
//     plus the one-time code plus the ES256 client secret.
//   - the user's name arrives once, on the first authorization, as a `user`
//     form field — never in the id_token.

const appleStateCookie = "apple_oauth_state"

func appleAvailabilityHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]bool{
		"available": appleOAuthConfigured() && dbPool != nil,
	})
}

func appleStartHandler(w http.ResponseWriter, r *http.Request) {
	if !appleOAuthConfigured() || dbPool == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "Apple sign-in is not configured")
		return
	}
	state, err := randomURLToken()
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "could not start sign-in")
		return
	}
	http.SetCookie(w, &http.Cookie{
		Name:     appleStateCookie,
		Value:    state,
		Path:     "/api/v1/auth/apple",
		MaxAge:   600,
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteNoneMode,
	})
	params := url.Values{
		"client_id":     {appleClientID()},
		"redirect_uri":  {appleRedirectURI()},
		"response_type": {"code"},
		"scope":         {"name email"},
		"response_mode": {"form_post"},
		"state":         {state},
	}
	http.Redirect(w, r, appleAuthURL()+"?"+params.Encode(), http.StatusFound)
}

// appleCallbackHandler receives Apple's form_post. It is still a top-level
// browser navigation, so every failure redirects to the app's /sso/error
// route (303 converts the POST to a GET).
func appleCallbackHandler(w http.ResponseWriter, r *http.Request) {
	redirectErr := func() {
		http.Redirect(w, r, publicAppURL("sso/", "error"), http.StatusSeeOther)
	}

	cookie, cookieErr := r.Cookie(appleStateCookie)
	http.SetCookie(w, &http.Cookie{
		Name: appleStateCookie, Value: "", Path: "/api/v1/auth/apple",
		MaxAge: -1, HttpOnly: true, Secure: true, SameSite: http.SameSiteNoneMode,
	})

	if !appleOAuthConfigured() || dbPool == nil {
		redirectErr()
		return
	}
	if err := r.ParseForm(); err != nil {
		redirectErr()
		return
	}
	if r.FormValue("error") != "" { // user cancelled the Apple sheet
		redirectErr()
		return
	}
	code := r.FormValue("code")
	state := r.FormValue("state")
	if code == "" || state == "" || cookieErr != nil || cookie.Value != state {
		redirectErr()
		return
	}

	claims, err := exchangeAppleCode(r.Context(), code)
	if err != nil {
		ctxLog(r.Context()).Error("apple oauth: code exchange failed", "error", err)
		redirectErr()
		return
	}

	user, err := findOrCreateAppleUser(r, claims, parseAppleUserField(r.FormValue("user")))
	if err != nil {
		ctxLog(r.Context()).Error("apple oauth: find-or-create failed", "error", err)
		redirectErr()
		return
	}

	handoff, err := issueEmailToken(r.Context(), store.New(dbPool), user, "sso", ssoHandoffTTL)
	if err != nil {
		ctxLog(r.Context()).Error("apple oauth: could not issue handoff code", "error", err)
		redirectErr()
		return
	}
	http.Redirect(w, r, publicAppURL("sso/", handoff), http.StatusSeeOther)
}

var errUnverifiedAppleEmail = errors.New("apple account email is missing or not verified")

// findOrCreateAppleUser applies the same linking rules as Google's: known sub
// signs in; a verified matching email auto-links; otherwise a new account is
// created. Hide-My-Email relay addresses are verified, deliverable-via-relay
// addresses — no special casing; they simply never match an existing account.
// formName is the once-only name from the `user` form field.
func findOrCreateAppleUser(r *http.Request, claims appleClaims, formName string) (store.User, error) {
	ctx := r.Context()
	q := store.New(dbPool)

	ident, err := q.GetAuthIdentity(ctx, store.GetAuthIdentityParams{
		Provider: "apple", ProviderUserID: claims.Sub,
	})
	if err == nil {
		return q.GetUserByID(ctx, ident.UserID)
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return store.User{}, err
	}

	email := strings.ToLower(strings.TrimSpace(claims.Email))
	if email == "" || !bool(claims.EmailVerified) {
		return store.User{}, errUnverifiedAppleEmail
	}

	user, err := q.GetUserByEmail(ctx, email)
	if errors.Is(err, pgx.ErrNoRows) {
		displayName := formName
		if displayName == "" {
			displayName = defaultDisplayName(email)
		}
		signupLocale := requestLocale(ctx)
		user, err = q.CreateUser(ctx, store.CreateUserParams{
			Email: email, PasswordHash: nil, DisplayName: &displayName,
			Locale: &signupLocale,
		})
		if err != nil {
			return store.User{}, err
		}
		go recordEvent(user.ID, "user_registered", nil, map[string]any{"method": "apple"})
	} else if err != nil {
		return store.User{}, err
	}

	if _, err := q.CreateAuthIdentity(ctx, store.CreateAuthIdentityParams{
		UserID: user.ID, Provider: "apple", ProviderUserID: claims.Sub, Email: &email,
	}); err != nil {
		return store.User{}, err
	}
	// Apple vouched for the address — no verification email needed.
	if err := q.MarkUserEmailVerified(ctx, user.ID); err != nil {
		return store.User{}, err
	}
	return q.GetUserByID(ctx, user.ID)
}
