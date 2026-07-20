package main

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Server-side localization (specs/i18n-spanish).
//
// The client resolves the locale (explicit override, else device language) and
// states it on every request via Accept-Language; the server never re-derives
// it. users.locale is consulted only where there is no request at all —
// background email jobs and token-gated exports.
//
// Scope is the text the API itself renders: emails, trip-review findings, the
// print/share export pages and .ics labels. The writeJSONError strings are
// deliberately NOT localized — they are developer- and edge-case-facing, and
// the right fix there is machine-readable error codes mapped client-side.
//
// The catalog is a plain map rather than golang.org/x/text/message: the
// server-side surface is a few dozen strings across a handful of locales, so a
// literal map stays greppable, dependency-free, and testable. TestCatalogIsComplete
// fails if any key is missing a translation, which is what keeps the fallback
// path from silently becoming the normal path.

const defaultLocale = "en"

const localeContextKey contextKey = "locale"

// supportedLocales is the source of truth for both negotiation and validation,
// most-preferred first. Adding a locale means: append here, add a languageNames
// entry, and fill in the catalog (the completeness test enforces the last one).
var supportedLocales = []string{"en", "es"}

// languageNames are English names for each locale, used to build the AI
// response-language instruction.
var languageNames = map[string]string{
	"en": "English",
	"es": "Spanish (español)",
}

// normalizeLocale folds a user- or header-supplied tag to a supported base
// language: "es-MX", "ES", "es-419" all become "es". Returns ok=false for
// anything unsupported, so callers can reject rather than silently defaulting.
func normalizeLocale(tag string) (string, bool) {
	base := strings.ToLower(strings.TrimSpace(tag))
	if i := strings.IndexAny(base, "-_"); i >= 0 {
		base = base[:i]
	}
	for _, l := range supportedLocales {
		if l == base {
			return l, true
		}
	}
	return "", false
}

// languageName returns the English name of a locale, for prompt text.
func languageName(locale string) string {
	if name, ok := languageNames[locale]; ok {
		return name
	}
	return languageNames[defaultLocale]
}

// matchLocale picks the best supported locale from an Accept-Language header,
// honoring q-values ("fr,es;q=0.9,en;q=0.8" => es, even though fr comes first).
// Unparseable, empty, and all-unsupported headers yield the default locale.
func matchLocale(header string) string {
	type candidate struct {
		tag string
		q   float64
		pos int
	}
	var candidates []candidate
	for i, part := range strings.Split(header, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		tag, q := part, 1.0
		if semi := strings.Index(part, ";"); semi >= 0 {
			tag = strings.TrimSpace(part[:semi])
			for _, param := range strings.Split(part[semi+1:], ";") {
				k, v, found := strings.Cut(param, "=")
				if !found || strings.ToLower(strings.TrimSpace(k)) != "q" {
					continue
				}
				if parsed, err := strconv.ParseFloat(strings.TrimSpace(v), 64); err == nil {
					q = parsed
				}
			}
		}
		// q=0 means "explicitly not acceptable".
		if q <= 0 {
			continue
		}
		if locale, ok := normalizeLocale(tag); ok {
			candidates = append(candidates, candidate{tag: locale, q: q, pos: i})
		}
	}
	if len(candidates) == 0 {
		return defaultLocale
	}
	// Highest q wins; ties break on header order, which is where browsers put
	// their real preference.
	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].q != candidates[j].q {
			return candidates[i].q > candidates[j].q
		}
		return candidates[i].pos < candidates[j].pos
	})
	return candidates[0].tag
}

// localeMiddleware stamps the negotiated locale onto the request context. It
// runs for every route — including the public token-gated export routes, which
// have no session to read a stored locale from.
func localeMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		locale := matchLocale(r.Header.Get("Accept-Language"))
		// An explicit ?lang= wins: export links are opened by a browser or a
		// calendar app whose own language says nothing about the traveler's.
		if q := r.URL.Query().Get("lang"); q != "" {
			if override, ok := normalizeLocale(q); ok {
				locale = override
			}
		}
		ctx := context.WithValue(r.Context(), localeContextKey, locale)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// requestLocale returns the locale negotiated for this request, or the default
// outside one. Never returns "", so every call site is safe without a guard.
func requestLocale(ctx context.Context) string {
	if locale, ok := ctx.Value(localeContextKey).(string); ok && locale != "" {
		return locale
	}
	return defaultLocale
}

// localeOrDefault resolves a stored (nullable) users.locale for the
// request-less callers: background email jobs and export fallbacks.
func localeOrDefault(stored *string) string {
	if stored == nil {
		return defaultLocale
	}
	if locale, ok := normalizeLocale(*stored); ok {
		return locale
	}
	return defaultLocale
}

// messages maps a stable key to its per-locale template. Templates are Sprintf
// format strings; argument order must match across locales, which is why
// multi-argument entries keep their placeholders in the same sequence.
var messages = map[string]map[string]string{
	"timeofday.morning":   {"en": "Morning", "es": "Mañana"},
	"timeofday.afternoon": {"en": "Afternoon", "es": "Tarde"},
	"timeofday.evening":   {"en": "Evening", "es": "Noche"},
	"common.day":          {"en": "Day %d", "es": "Día %d"},
	"common.unscheduled":  {"en": "Unscheduled", "es": "Sin programar"},
}

// tr renders a catalog entry in the given locale, falling back to English and
// then to the key itself, so a missing translation degrades to readable text
// rather than a blank. Args are applied with Sprintf when present.
func tr(locale, key string, args ...any) string {
	template, ok := lookupMessage(locale, key)
	if !ok {
		return key
	}
	if len(args) == 0 {
		return template
	}
	return fmt.Sprintf(template, args...)
}

func lookupMessage(locale, key string) (string, bool) {
	entry, ok := messages[key]
	if !ok {
		return "", false
	}
	if template, ok := entry[locale]; ok && template != "" {
		return template, true
	}
	template, ok := entry[defaultLocale]
	return template, ok
}

// Date formatting. Go's time.Format hardcodes English month and weekday names,
// so localized dates need their own tables rather than a layout string.

const (
	dateStyleMonthDay        = "monthDay"        // Jan 2      / 2 ene
	dateStyleWeekdayMonthDay = "weekdayMonthDay" // Mon, Jan 2 / lun, 2 ene
	dateStyleLong            = "long"            // January 2, 2026 / 2 de enero de 2026
)

var esMonthsShort = [...]string{"ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"}

var esMonthsLong = [...]string{
	"enero", "febrero", "marzo", "abril", "mayo", "junio",
	"julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
}

// Indexed by time.Weekday (Sunday = 0).
var esWeekdaysShort = [...]string{"dom", "lun", "mar", "mié", "jue", "vie", "sáb"}

// localizedDate renders t in the given style and locale. Spanish uses
// day-before-month ordering, which is why this switches on locale rather than
// swapping a layout string.
func localizedDate(locale string, t time.Time, style string) string {
	if locale != "es" {
		switch style {
		case dateStyleWeekdayMonthDay:
			return t.Format("Mon, Jan 2")
		case dateStyleLong:
			return t.Format("January 2, 2006")
		default:
			return t.Format("Jan 2")
		}
	}
	month := int(t.Month()) - 1
	switch style {
	case dateStyleWeekdayMonthDay:
		return fmt.Sprintf("%s, %d %s", esWeekdaysShort[t.Weekday()], t.Day(), esMonthsShort[month])
	case dateStyleLong:
		return fmt.Sprintf("%d de %s de %d", t.Day(), esMonthsLong[month], t.Year())
	default:
		return fmt.Sprintf("%d %s", t.Day(), esMonthsShort[month])
	}
}
