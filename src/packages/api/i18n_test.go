package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestNormalizeLocale(t *testing.T) {
	cases := []struct {
		in     string
		want   string
		wantOK bool
	}{
		{"en", "en", true},
		{"es", "es", true},
		{"ES", "es", true},
		{"  es  ", "es", true},
		{"es-MX", "es", true},
		{"es-419", "es", true},
		{"es_ES", "es", true},
		{"en-GB", "en", true},
		{"fr", "", false},
		{"", "", false},
		{"esperanto", "", false}, // must not prefix-match "es"
	}
	for _, c := range cases {
		got, ok := normalizeLocale(c.in)
		if got != c.want || ok != c.wantOK {
			t.Errorf("normalizeLocale(%q) = (%q, %v), want (%q, %v)", c.in, got, ok, c.want, c.wantOK)
		}
	}
}

func TestMatchLocale(t *testing.T) {
	cases := []struct {
		header string
		want   string
	}{
		{"", "en"},
		{"es", "es"},
		{"es-MX", "es"},
		{"es-MX,es;q=0.9,en;q=0.8", "es"},
		{"en-US,en;q=0.9", "en"},
		// Highest q wins even when it is not first in the header.
		{"fr,es;q=0.9,en;q=0.8", "es"},
		{"fr-CA,de;q=0.7", "en"}, // nothing supported => default
		{"*", "en"},
		{"es;q=0", "en"},              // explicitly not acceptable
		{"es;q=bogus,en;q=0.1", "es"}, // unparseable q falls back to 1.0
		{"  ,  , es ", "es"},
		// Equal q ties break on header order.
		{"en;q=0.9,es;q=0.9", "en"},
		{"es;q=0.9,en;q=0.9", "es"},
	}
	for _, c := range cases {
		if got := matchLocale(c.header); got != c.want {
			t.Errorf("matchLocale(%q) = %q, want %q", c.header, got, c.want)
		}
	}
}

func TestLocaleMiddlewareStampsContext(t *testing.T) {
	cases := []struct {
		name   string
		header string
		path   string
		want   string
	}{
		{"no header defaults to english", "", "/x", "en"},
		{"header negotiated", "es-MX,es;q=0.9", "/x", "es"},
		{"lang query overrides header", "en-US", "/x?lang=es", "es"},
		{"unsupported lang query ignored", "es", "/x?lang=fr", "es"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			var got string
			h := localeMiddleware(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
				got = requestLocale(r.Context())
			}))
			req := httptest.NewRequest("GET", c.path, nil)
			if c.header != "" {
				req.Header.Set("Accept-Language", c.header)
			}
			h.ServeHTTP(httptest.NewRecorder(), req)
			if got != c.want {
				t.Errorf("requestLocale = %q, want %q", got, c.want)
			}
		})
	}
}

// requestLocale must be safe to call from background jobs and tests that never
// went through the middleware.
func TestRequestLocaleOutsideRequest(t *testing.T) {
	if got := requestLocale(context.Background()); got != "en" {
		t.Errorf("requestLocale(bare ctx) = %q, want en", got)
	}
}

func TestLocaleOrDefault(t *testing.T) {
	es, bogus := "es-MX", "klingon"
	cases := []struct {
		in   *string
		want string
	}{
		{nil, "en"},
		{&es, "es"},
		{&bogus, "en"},
	}
	for _, c := range cases {
		if got := localeOrDefault(c.in); got != c.want {
			t.Errorf("localeOrDefault(%v) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestTrFallsBackToEnglishThenKey(t *testing.T) {
	if got := tr("es", "timeofday.morning"); got != "Mañana" {
		t.Errorf("es translation = %q, want Mañana", got)
	}
	// An unknown locale must not blank the string — English is the floor.
	if got := tr("fr", "timeofday.morning"); got != "Morning" {
		t.Errorf("unknown-locale fallback = %q, want Morning", got)
	}
	// An unknown key degrades to the key itself, which is readable in a log or
	// a page rather than an empty gap.
	if got := tr("es", "nope.not.a.key"); got != "nope.not.a.key" {
		t.Errorf("unknown-key fallback = %q, want the key", got)
	}
	if got := tr("es", "common.day", 3); got != "Día 3" {
		t.Errorf("templated = %q, want Día 3", got)
	}
}

// The catalog's fallback path exists for safety, not for daily use: every key
// must carry every supported locale, or Spanish users silently read English.
func TestCatalogIsComplete(t *testing.T) {
	for key, entry := range messages {
		for _, locale := range supportedLocales {
			if entry[locale] == "" {
				t.Errorf("message %q is missing a %q translation", key, locale)
			}
		}
	}
	for _, locale := range supportedLocales {
		if languageNames[locale] == "" {
			t.Errorf("locale %q has no languageNames entry", locale)
		}
	}
}

func TestLocalizedDate(t *testing.T) {
	// A Monday, to exercise the weekday table.
	d := time.Date(2026, time.January, 5, 12, 0, 0, 0, time.UTC)
	cases := []struct {
		locale, style, want string
	}{
		{"en", dateStyleMonthDay, "Jan 5"},
		{"en", dateStyleWeekdayMonthDay, "Mon, Jan 5"},
		{"en", dateStyleLong, "January 5, 2026"},
		{"es", dateStyleMonthDay, "5 ene"},
		{"es", dateStyleWeekdayMonthDay, "lun, 5 ene"},
		{"es", dateStyleLong, "5 de enero de 2026"},
		// Unknown locales take the English path rather than panicking.
		{"fr", dateStyleLong, "January 5, 2026"},
	}
	for _, c := range cases {
		if got := localizedDate(c.locale, d, c.style); got != c.want {
			t.Errorf("localizedDate(%q, %q) = %q, want %q", c.locale, c.style, got, c.want)
		}
	}
}

func TestLanguageName(t *testing.T) {
	if got := languageName("es"); got != "Spanish (español)" {
		t.Errorf("languageName(es) = %q", got)
	}
	if got := languageName("zz"); got != "English" {
		t.Errorf("languageName(unknown) = %q, want English", got)
	}
}
