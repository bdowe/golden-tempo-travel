package main

import (
	"html/template"
	"net/http"
	"strings"

	"travel-route-planner/store"
)

// Link previews for shared trips. Crawlers (Slack/iMessage/WhatsApp/Twitter…)
// don't execute JS, so the SPA share page renders blank for them. The
// deployment nginx UA-sniffs known bots on /app/share/* and rewrites here;
// humans keep the clean app URL and never touch this page (the meta-refresh
// below is only a fallback for bot-like browsers).

// sharePreviewTmpl uses html/template — all fields are auto-escaped; never
// build this page with fmt.Sprintf.
var sharePreviewTmpl = template.Must(template.New("share-preview").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{{.Title}} — Golden Tempo Travel</title>
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Golden Tempo Travel">
  <meta property="og:title" content="{{.Title}}">
  <meta property="og:description" content="{{.Description}}">
  <meta property="og:url" content="{{.URL}}">
  <meta property="og:image" content="{{.Image}}">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="{{.Title}}">
  <meta name="twitter:description" content="{{.Description}}">
  <meta http-equiv="refresh" content="0;url={{.URL}}">
</head>
<body>
  <p><a href="{{.URL}}">{{.Title}}</a> — {{.Description}}</p>
</body>
</html>`))

type sharePreviewData struct {
	Title       string
	Description string
	URL         string
	Image       string
}

// previewBaseURL reconstructs the public origin from the proxy headers the
// nginx gateway already sets; falls back to the request host.
func previewBaseURL(r *http.Request) string {
	scheme := r.Header.Get("X-Forwarded-Proto")
	if scheme == "" {
		scheme = "http"
	}
	return scheme + "://" + r.Host
}

// truncatePreview keeps OG text within preview-card limits at a rune
// boundary.
func truncatePreview(s string, max int) string {
	runes := []rune(strings.TrimSpace(s))
	if len(runes) <= max {
		return string(runes)
	}
	return strings.TrimSpace(string(runes[:max-1])) + "…"
}

// sharePreviewHandler is GET /api/v1/share-preview/{token}: a minimal HTML
// page with OG tags for link-preview crawlers. Same data path and 404
// posture as sharedTripHandler; no new queries.
func sharePreviewHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if dbPool == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		w.Write([]byte("<html><body><h2>Temporarily unavailable</h2></body></html>"))
		return
	}
	share, trip, ok := resolveShare(r)
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("<html><body><h2>This trip isn't available</h2><p>The link may have been turned off.</p></body></html>"))
		return
	}

	ownerName := "a traveler"
	if owner, err := store.New(dbPool).GetUserByID(r.Context(), share.OwnerID); err == nil &&
		owner.DisplayName != nil && *owner.DisplayName != "" {
		ownerName = *owner.DisplayName
	}

	var descParts []string
	if trip.StartDate.Valid && trip.EndDate.Valid {
		descParts = append(descParts,
			trip.StartDate.Time.Format("Jan 2")+" – "+trip.EndDate.Time.Format("Jan 2, 2006"))
	}
	descParts = append(descParts, "Planned by "+ownerName)
	if trip.Summary != nil {
		if first := strings.TrimSpace(strings.SplitN(*trip.Summary, "\n", 2)[0]); first != "" {
			descParts = append(descParts, first)
		}
	}

	base := previewBaseURL(r)
	data := sharePreviewData{
		Title:       truncatePreview(trip.Title, 70),
		Description: truncatePreview(strings.Join(descParts, " · "), 200),
		URL:         base + "/app/share/" + share.Token,
		Image:       base + "/app/icons/Icon-512.png",
	}
	if err := sharePreviewTmpl.Execute(w, data); err != nil {
		// Headers already sent; nothing sensible left to do.
		return
	}
}
