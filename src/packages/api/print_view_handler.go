package main

import (
	"html/template"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gorilla/mux"

	"travel-route-planner/store"
)

// capitalize upper-cases the first rune of a lower-case token (e.g. "morning" →
// "Morning", "flight" → "Flight") for display. Avoids the deprecated
// strings.Title while covering these single-word values.
func capitalize(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return ""
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// print_view_handler.go — GET /api/v1/export/{token}/print.html, a printable
// full-trip page. Token-gated and PUBLIC (no authMiddleware): the signed token
// is the capability. Rendered with html/template so every field is
// auto-escaped; NEVER assemble this HTML with fmt.Sprintf (same rule as
// share_preview_handler.go).

type printItem struct {
	Name          string
	TimeOfDay     string
	Address       string
	RecommendedBy string // local_source_name attribution, when present
}

type printDay struct {
	Label string // "Day 3" / "Unscheduled"
	Date  string // "Mon, Jan 2" or "" when undatable
	Items []printItem
}

type printGroup struct {
	Hub  string // day_trip_from → city → "Itinerary"
	Days []printDay
}

type printStay struct {
	Name     string
	Address  string
	CheckIn  string
	CheckOut string
}

type printSegment struct {
	Mode   string
	Route  string // "Origin → Destination"
	Depart string
	Arrive string
}

type printTodo struct {
	Title    string
	Subtitle string
	Booked   bool
}

type printChecklistGroup struct {
	Category string
	Items    []printChecklistItem
}

type printChecklistItem struct {
	Title   string
	Checked bool
}

type printViewData struct {
	Title      string
	Dates      string
	Groups     []printGroup
	Stays      []printStay
	Segments   []printSegment
	Todos      []printTodo
	Checklist  []printChecklistGroup
	HasContent bool
}

// printViewTmpl uses html/template — every field is auto-escaped. Brand house
// style (teal gradient header) cloned from dockerize/static/privacy.html.
var printViewTmpl = template.Must(template.New("print-view").Parse(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{{.Title}} — Golden Tempo Travel</title>
  <style>
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      color: #263238; background: #fff; line-height: 1.55;
    }
    header {
      background: linear-gradient(to bottom right, #00897B, #004D40);
      color: #fff; padding: 32px 24px 28px;
    }
    header .wrap { max-width: 820px; margin: 0 auto; }
    header .brand {
      font-size: 0.8rem; letter-spacing: 0.08em; text-transform: uppercase;
      opacity: 0.85; margin: 0 0 6px; display: flex; align-items: center; gap: 10px;
    }
    header .brand img { height: 22px; width: 22px; border-radius: 5px; }
    header h1 { margin: 0; font-size: 1.7rem; }
    header .meta { margin: 8px 0 0; opacity: 0.9; font-size: 0.95rem; }
    main { max-width: 820px; margin: 0 auto; padding: 28px 24px 56px; }
    h2 {
      color: #00695C; font-size: 1.2rem; margin: 32px 0 8px;
      border-bottom: 2px solid #B2DFDB; padding-bottom: 6px;
    }
    .hub { margin: 20px 0 0; }
    .hub-name { font-size: 1.05rem; font-weight: 600; color: #004D40; margin: 0 0 4px; }
    .day { margin: 12px 0 0; padding: 10px 14px; background: #F5F7F7; border-radius: 8px; }
    .day-head { font-weight: 600; color: #00695C; margin: 0 0 6px; }
    .item { margin: 6px 0; padding-left: 14px; border-left: 3px solid #B2DFDB; }
    .item-name { font-weight: 600; }
    .item-meta { font-size: 0.9rem; color: #546E7A; }
    .rec { font-size: 0.88rem; color: #00695C; font-style: italic; }
    .row { padding: 8px 0; border-bottom: 1px solid #ECEFF1; }
    .row:last-child { border-bottom: none; }
    .row-title { font-weight: 600; }
    .row-meta { font-size: 0.9rem; color: #546E7A; }
    .cat { font-weight: 600; color: #004D40; margin: 14px 0 4px; text-transform: capitalize; }
    ul.check { list-style: none; padding-left: 0; margin: 0; }
    ul.check li { padding: 3px 0; }
    .box { display: inline-block; width: 1em; }
    .booked { color: #2E7D32; }
    footer { margin-top: 40px; padding-top: 14px; border-top: 1px solid #CFD8DC; font-size: 0.85rem; color: #607D8B; }
    .empty { color: #607D8B; font-style: italic; }
    @media print {
      header { background: #004D40 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
      .day, .hub, .row { page-break-inside: avoid; }
      h2 { page-break-after: avoid; }
    }
  </style>
</head>
<body>
  <header>
    <div class="wrap">
      <p class="brand"><img src="/app/icons/Icon-512.png" alt="">Golden Tempo Travel</p>
      <h1>{{.Title}}</h1>
      {{if .Dates}}<p class="meta">{{.Dates}}</p>{{end}}
    </div>
  </header>
  <main>
    {{if not .HasContent}}<p class="empty">This trip has nothing to export yet.</p>{{end}}

    {{if .Groups}}
    <h2>Itinerary</h2>
    {{range .Groups}}
    <div class="hub">
      <p class="hub-name">{{.Hub}}</p>
      {{range .Days}}
      <div class="day">
        <p class="day-head">{{.Label}}{{if .Date}} · {{.Date}}{{end}}</p>
        {{range .Items}}
        <div class="item">
          <div class="item-name">{{.Name}}</div>
          {{if or .TimeOfDay .Address}}<div class="item-meta">{{if .TimeOfDay}}{{.TimeOfDay}}{{end}}{{if and .TimeOfDay .Address}} · {{end}}{{.Address}}</div>{{end}}
          {{if .RecommendedBy}}<div class="rec">Recommended by {{.RecommendedBy}}</div>{{end}}
        </div>
        {{end}}
      </div>
      {{end}}
    </div>
    {{end}}
    {{end}}

    {{if .Stays}}
    <h2>Accommodations</h2>
    {{range .Stays}}
    <div class="row">
      <div class="row-title">{{.Name}}</div>
      {{if .Address}}<div class="row-meta">{{.Address}}</div>{{end}}
      {{if or .CheckIn .CheckOut}}<div class="row-meta">{{if .CheckIn}}Check-in {{.CheckIn}}{{end}}{{if .CheckOut}} · Check-out {{.CheckOut}}{{end}}</div>{{end}}
    </div>
    {{end}}
    {{end}}

    {{if .Segments}}
    <h2>Transport</h2>
    {{range .Segments}}
    <div class="row">
      <div class="row-title">{{.Route}}</div>
      <div class="row-meta">{{.Mode}}{{if .Depart}} · Departs {{.Depart}}{{end}}{{if .Arrive}} · Arrives {{.Arrive}}{{end}}</div>
    </div>
    {{end}}
    {{end}}

    {{if .Todos}}
    <h2>Booking checklist</h2>
    {{range .Todos}}
    <div class="row">
      <div class="row-title"><span class="box">{{if .Booked}}&#9745;{{else}}&#9744;{{end}}</span> {{.Title}}{{if .Booked}} <span class="booked">(booked)</span>{{end}}</div>
      {{if .Subtitle}}<div class="row-meta">{{.Subtitle}}</div>{{end}}
    </div>
    {{end}}
    {{end}}

    {{if .Checklist}}
    <h2>Packing checklist</h2>
    {{range .Checklist}}
    <p class="cat">{{.Category}}</p>
    <ul class="check">
      {{range .Items}}<li><span class="box">{{if .Checked}}&#9745;{{else}}&#9744;{{end}}</span> {{.Title}}</li>{{end}}
    </ul>
    {{end}}
    {{end}}

    <footer>Exported from Golden Tempo Travel</footer>
  </main>
</body>
</html>`))

// printViewHandler renders the full trip as a printable HTML page.
func printViewHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	data, ok := resolveExport(r, mux.Vars(r)["token"])
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		w.Write([]byte("<!DOCTYPE html><html><body><h2>This export link isn't available</h2><p>It may have expired.</p></body></html>"))
		return
	}
	view := buildPrintView(data)
	if err := printViewTmpl.Execute(w, view); err != nil {
		// Headers already sent; nothing sensible left to do.
		return
	}
}

// buildPrintView reshapes the raw export data into the template view model:
// items grouped by hub (day_trip_from → city) then by day with resolved dates,
// plus flat stays/segments/todos/checklist sections.
func buildPrintView(d exportData) printViewData {
	view := printViewData{Title: strings.TrimSpace(d.Trip.Title)}
	if view.Title == "" {
		view.Title = "Untitled trip"
	}
	if d.Trip.StartDate.Valid && d.Trip.EndDate.Valid {
		view.Dates = d.Trip.StartDate.Time.Format("Jan 2") + " – " + d.Trip.EndDate.Time.Format("Jan 2, 2006")
	} else if d.Trip.StartDate.Valid {
		view.Dates = d.Trip.StartDate.Time.Format("Jan 2, 2006")
	}

	view.Groups = groupExportItems(d.Trip, d.Items)

	for _, a := range d.Accommodations {
		view.Stays = append(view.Stays, printStay{
			Name:     a.Name,
			Address:  strPtrVal(a.Address),
			CheckIn:  formatExportDate(dateToPtr(a.CheckIn)),
			CheckOut: formatExportDate(dateToPtr(a.CheckOut)),
		})
	}
	for _, s := range d.Segments {
		view.Segments = append(view.Segments, printSegment{
			Mode:   capitalize(s.Mode),
			Route:  segmentRoute(s),
			Depart: formatExportDate(dateToPtr(s.DepartDate)),
			Arrive: formatExportDate(dateToPtr(s.ArriveDate)),
		})
	}
	for _, t := range d.BookingTodos {
		view.Todos = append(view.Todos, printTodo{
			Title:    t.Title,
			Subtitle: strPtrVal(t.Subtitle),
			Booked:   t.Booked,
		})
	}
	view.Checklist = groupChecklist(d.Checklist)

	view.HasContent = len(view.Groups) > 0 || len(view.Stays) > 0 ||
		len(view.Segments) > 0 || len(view.Todos) > 0 || len(view.Checklist) > 0
	return view
}

// groupExportItems walks items in position order and groups them by hub
// (day_trip_from, falling back to city, then "Itinerary"), sub-grouping by day.
// First-appearance order is preserved for both hubs and days. Per-item date is
// trip.start_date + (day-1) when both are present.
func groupExportItems(trip store.Trip, items []store.ItineraryItem) []printGroup {
	var groups []printGroup
	groupIdx := map[string]int{}
	dayIdx := map[string]int{} // key: hub + "\x00" + day

	for _, it := range items {
		hub := strings.TrimSpace(strPtrVal(it.DayTripFrom))
		if hub == "" {
			hub = strings.TrimSpace(strPtrVal(it.City))
		}
		if hub == "" {
			hub = "Itinerary"
		}
		gi, ok := groupIdx[hub]
		if !ok {
			gi = len(groups)
			groupIdx[hub] = gi
			groups = append(groups, printGroup{Hub: hub})
		}

		dayNum := 0
		if it.Day != nil {
			dayNum = int(*it.Day)
		}
		dayKey := hub + "\x00" + strconv.Itoa(dayNum)
		di, ok := dayIdx[dayKey]
		if !ok {
			di = len(groups[gi].Days)
			dayIdx[dayKey] = di
			label := "Unscheduled"
			date := ""
			if dayNum > 0 {
				label = "Day " + strconv.Itoa(dayNum)
				if trip.StartDate.Valid {
					date = trip.StartDate.Time.AddDate(0, 0, dayNum-1).Format("Mon, Jan 2")
				}
			}
			groups[gi].Days = append(groups[gi].Days, printDay{Label: label, Date: date})
		}

		groups[gi].Days[di].Items = append(groups[gi].Days[di].Items, printItem{
			Name:          it.Name,
			TimeOfDay:     capitalize(strPtrVal(it.TimeOfDay)),
			Address:       strPtrVal(it.Address),
			RecommendedBy: strPtrVal(it.LocalSourceName),
		})
	}
	return groups
}

// groupChecklist buckets packing items by category, preserving first-appearance
// order (items already arrive sorted by position).
func groupChecklist(items []store.TripChecklistItem) []printChecklistGroup {
	var groups []printChecklistGroup
	idx := map[string]int{}
	for _, it := range items {
		gi, ok := idx[it.Category]
		if !ok {
			gi = len(groups)
			idx[it.Category] = gi
			groups = append(groups, printChecklistGroup{Category: it.Category})
		}
		groups[gi].Items = append(groups[gi].Items, printChecklistItem{Title: it.Title, Checked: it.Checked})
	}
	return groups
}

// segmentRoute renders "Origin → Destination", tolerating missing endpoints.
func segmentRoute(s store.TripSegment) string {
	o := strings.TrimSpace(strPtrVal(s.Origin))
	dst := strings.TrimSpace(strPtrVal(s.Destination))
	switch {
	case o != "" && dst != "":
		return o + " → " + dst
	case dst != "":
		return dst
	case o != "":
		return o
	default:
		return capitalize(s.Mode)
	}
}

// formatExportDate turns a *string "YYYY-MM-DD" into a friendly "Mon, Jan 2".
func formatExportDate(s *string) string {
	if s == nil || *s == "" {
		return ""
	}
	t, err := time.Parse(dateLayout, *s)
	if err != nil {
		return *s
	}
	return t.Format("Mon, Jan 2")
}
