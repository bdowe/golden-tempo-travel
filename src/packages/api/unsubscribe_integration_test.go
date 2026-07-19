package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"travel-route-planner/store"
)

// optOutFlags reads the two email opt-out columns straight from the DB.
func optOutFlags(t *testing.T, userID interface{ String() string }) (reminders, nudges bool) {
	t.Helper()
	if err := dbPool.QueryRow(t.Context(),
		`SELECT reminders_opt_out, nudges_opt_out FROM users WHERE id = $1`,
		userID).Scan(&reminders, &nudges); err != nil {
		t.Fatalf("read opt-out flags: %v", err)
	}
	return
}

// doUnsub drives the public unsubscribe route (no auth).
func doUnsub(t *testing.T, method, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, "/api/v1/unsubscribe/"+token, nil)
	req.Header.Set("X-Forwarded-For", nextTestIP())
	rec := httptest.NewRecorder()
	testRouter.ServeHTTP(rec, req)
	return rec
}

func TestUnsubscribe_FlipsFlagPerCategory(t *testing.T) {
	resetDB(t)
	user, _ := createTestUser(t, "unsub@example.com")

	// Default: both opted-in (opt_out false).
	if r, n := optOutFlags(t, user.ID); r || n {
		t.Fatalf("new user should be opted-in, got reminders_opt_out=%v nudges_opt_out=%v", r, n)
	}

	// Nudges link flips only nudges.
	tok := newUnsubscribeToken(user.ID, unsubNudges)
	if rec := doUnsub(t, "GET", tok); rec.Code != http.StatusOK {
		t.Fatalf("unsubscribe nudges = %d: %s", rec.Code, rec.Body.String())
	}
	if r, n := optOutFlags(t, user.ID); r || !n {
		t.Fatalf("after nudges unsub: reminders_opt_out=%v nudges_opt_out=%v, want false/true", r, n)
	}

	// Idempotent: clicking again still 200, still opted-out.
	if rec := doUnsub(t, "GET", tok); rec.Code != http.StatusOK {
		t.Fatalf("idempotent unsubscribe = %d", rec.Code)
	}
	if _, n := optOutFlags(t, user.ID); !n {
		t.Fatal("second unsubscribe should keep nudges opted-out")
	}

	// "all" flips both.
	allTok := newUnsubscribeToken(user.ID, unsubAll)
	if rec := doUnsub(t, "POST", allTok); rec.Code != http.StatusOK {
		t.Fatalf("unsubscribe all (POST) = %d: %s", rec.Code, rec.Body.String())
	}
	if r, n := optOutFlags(t, user.ID); !r || !n {
		t.Fatalf("after all unsub: reminders_opt_out=%v nudges_opt_out=%v, want true/true", r, n)
	}
}

func TestUnsubscribe_InvalidToken(t *testing.T) {
	resetDB(t)
	for _, bad := range []string{"garbage", "a.b", "not-a-token"} {
		if rec := doUnsub(t, "GET", bad); rec.Code != http.StatusNotFound {
			t.Fatalf("bad token %q = %d, want 404", bad, rec.Code)
		}
	}
}

func TestUnsubscribe_WrongUserGone(t *testing.T) {
	resetDB(t)
	user, _ := createTestUser(t, "gone-soon@example.com")
	tok := newUnsubscribeToken(user.ID, unsubReminders)
	// Delete the user, then the token points at nobody.
	if _, err := store.New(dbPool).DeleteUser(t.Context(), user.ID); err != nil {
		t.Fatal(err)
	}
	if rec := doUnsub(t, "GET", tok); rec.Code != http.StatusNotFound {
		t.Fatalf("deleted-user token = %d, want 404", rec.Code)
	}
}

func TestEmailPreferences_PatchAndMe(t *testing.T) {
	resetDB(t)
	_, token := createTestUser(t, "prefs@example.com")

	// /auth/me reflects defaults: both enabled.
	me := decode(t, doJSON(t, "GET", "/api/v1/auth/me", token, nil))
	if me["reminders_enabled"] != true || me["nudges_enabled"] != true {
		t.Fatalf("default prefs: %v", me)
	}

	// Toggle nudges off via PATCH.
	rec := doJSON(t, "PATCH", "/api/v1/auth/email-preferences", token, map[string]any{
		"nudges_enabled": false,
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("patch prefs = %d: %s", rec.Code, rec.Body.String())
	}
	body := decode(t, rec)
	if body["nudges_enabled"] != false || body["reminders_enabled"] != true {
		t.Fatalf("after patch: %v", body)
	}

	// Persisted on next /auth/me.
	me2 := decode(t, doJSON(t, "GET", "/api/v1/auth/me", token, nil))
	if me2["nudges_enabled"] != false {
		t.Fatalf("nudges pref not persisted: %v", me2)
	}
}
