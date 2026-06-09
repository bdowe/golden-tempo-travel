package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/chromedp/cdproto/page"
	"github.com/chromedp/chromedp"
)

// --- Request / Response types ---

type AirbnbParseRequest struct {
	URL string `json:"url"`
}

type AirbnbListingLocation struct {
	City      string  `json:"city"`
	State     string  `json:"state"`
	Country   string  `json:"country"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

type AirbnbHost struct {
	Name   string `json:"name"`
	Avatar string `json:"avatar"`
}

type AirbnbPhoto struct {
	URL     string `json:"url"`
	Caption string `json:"caption"`
}

type AirbnbPricing struct {
	NightlyRate float64 `json:"nightly_rate"`
	Nights      int     `json:"nights"`
	CleaningFee float64 `json:"cleaning_fee"`
	ServiceFee  float64 `json:"service_fee"`
	Total       float64 `json:"total"`
	Currency    string  `json:"currency"`
}

type AirbnbListing struct {
	ListingID    string                `json:"listing_id"`
	URL          string                `json:"url"`
	Title        string                `json:"title"`
	Description  string                `json:"description"`
	PropertyType string                `json:"property_type"`
	RoomType     string                `json:"room_type"`
	MaxGuests    int                   `json:"max_guests"`
	Bedrooms     int                   `json:"bedrooms"`
	Bathrooms    float64               `json:"bathrooms"`
	Beds         int                   `json:"beds"`
	Location     AirbnbListingLocation `json:"location"`
	Host         AirbnbHost            `json:"host"`
	Rating       float64               `json:"rating"`
	ReviewCount  int                   `json:"review_count"`
	Photos       []AirbnbPhoto         `json:"photos"`
	Amenities    []string              `json:"amenities"`
	CheckIn      string                `json:"check_in"`
	CheckOut     string                `json:"check_out"`
	Pricing      AirbnbPricing         `json:"pricing"`
}

// --- AirbnbService ---

type AirbnbService struct {
	chromeWsURL string // empty → launch local Chrome via exec allocator
}

func NewAirbnbService() *AirbnbService {
	return &AirbnbService{
		chromeWsURL: getEnv("CHROME_WS_URL", ""),
	}
}

// newContext creates a chromedp context, connecting to a remote Chrome instance
// when CHROME_WS_URL is set (Docker), or launching a local Chrome otherwise.
func (s *AirbnbService) newContext(parent context.Context) (context.Context, context.CancelFunc) {
	if s.chromeWsURL != "" {
		allocCtx, allocCancel := chromedp.NewRemoteAllocator(parent, s.chromeWsURL)
		taskCtx, taskCancel := chromedp.NewContext(allocCtx)
		return taskCtx, func() { taskCancel(); allocCancel() }
	}
	// Local mode: launch Chrome directly (requires Chrome/Chromium installed)
	opts := append(chromedp.DefaultExecAllocatorOptions[:],
		chromedp.Flag("no-sandbox", true),
		chromedp.Flag("disable-dev-shm-usage", true),
		chromedp.Flag("disable-gpu", true),
	)
	allocCtx, allocCancel := chromedp.NewExecAllocator(parent, opts...)
	taskCtx, taskCancel := chromedp.NewContext(allocCtx)
	return taskCtx, func() { taskCancel(); allocCancel() }
}

var listingIDRe = regexp.MustCompile(`/rooms/(\d+)`)

func extractListingID(rawURL string) string {
	m := listingIDRe.FindStringSubmatch(rawURL)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

func stripQuery(rawURL string) string {
	u, err := url.Parse(rawURL)
	if err != nil {
		return rawURL
	}
	u.RawQuery = ""
	return u.String()
}

type DebugInfo struct {
	PageTitle       string                 `json:"page_title"`
	CurrentURL      string                 `json:"current_url"`
	CapturedURLs    []string               `json:"captured_urls"`
	CaptureCount    int                    `json:"capture_count"`
	Structure       map[string]interface{} `json:"structure"`
	SectionsSummary interface{}            `json:"sections_summary"`
	PricingSummary  interface{}            `json:"pricing_summary"`
	DOMSummary      interface{}            `json:"dom_summary"`
}

// FetchDebugInfo loads the page with the fetch interceptor and returns the
// captured API URLs plus a depth-limited structure summary of each payload.
func (s *AirbnbService) FetchDebugInfo(rawURL string) (*DebugInfo, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Second)
	defer cancel()

	taskCtx, taskCancel := s.newContext(ctx)
	defer taskCancel()

	var pageTitle, currentURL, capturedJSON, sectionsSummaryJSON, pricingSummaryJSON, domSummaryJSON string

	// Merges sections from ALL StaysPdpSections responses (Airbnb makes 2+ calls).
	const sectionsJS = `(() => {
		const caps = window.__captures || {};
		const url = Object.keys(caps).find(k => k.includes('StaysPdpSections'));
		if (!url) return JSON.stringify({error: 'StaysPdpSections not captured'});
		const responses = caps[url]; // now an array
		const allSections = [];
		for (const d of responses) {
			const sections =
				(d?.data?.presentation?.stayProductDetailPage?.sections?.sections) ||
				(d?.data?.node?.pdpPresentation?.sections?.sections) || [];
			if (Array.isArray(sections)) allSections.push(...sections);
		}
		return JSON.stringify(allSections.map(s => ({
			sectionId: s.sectionId,
			typename:  s.section?.__typename,
			keys:      Object.keys(s.section || {})
		})));
	})()`

	// Digs into BOOK_IT_SIDEBAR.structuredDisplayPrice for the price breakdown.
	const pricingJS = `(() => {
		const caps = window.__captures || {};
		const url = Object.keys(caps).find(k => k.includes('StaysPdpSections'));
		if (!url) return JSON.stringify({error: 'not found'});
		const allSections = [];
		for (const d of (caps[url] || [])) {
			const ss = d?.data?.presentation?.stayProductDetailPage?.sections?.sections || [];
			allSections.push(...ss);
		}
		const bookIt = allSections.find(s => s.sectionId === 'BOOK_IT_SIDEBAR')?.section || {};
		const sdp = bookIt.structuredDisplayPrice || {};
		return JSON.stringify({
			selectedNights:        bookIt.selectedNights,
			maxGuestCapacity:      bookIt.maxGuestCapacity,
			structuredDisplayPrice: sdp,
			descriptionItems:      bookIt.descriptionItems
		});
	})()`

	const domInspectJS = `(() => {
		const $$ = sel => Array.from(document.querySelectorAll(sel));
		const seen = new Set();
		const sectionIds = $$('[data-section-id]').map(el => el.getAttribute('data-section-id')).filter(Boolean);
		const photos = $$('img[src*="muscache.com"]')
			.map(img => img.src)
			.filter(u => !seen.has(u) && seen.add(u));
		const h1 = document.querySelector('h1');
		const title = h1 ? h1.innerText?.trim() : '';
		const sectionTexts = {};
		const seenIds = {};
		const interesting = ['OVERVIEW_DEFAULT_V2','DESCRIPTION_DEFAULT','AMENITIES_DEFAULT','MEET_YOUR_HOST','HOST_OVERVIEW_DEFAULT','LOCATION_DEFAULT','REVIEWS_DEFAULT'];
		$$('[data-section-id]').forEach(el => {
			const id = el.getAttribute('data-section-id');
			if (id) seenIds[id] = (seenIds[id] || 0) + 1;
			if (id && interesting.includes(id)) {
				const text = el.innerText?.trim()?.substring(0, 500) || '';
				if (text) sectionTexts[id] = text;
			}
		});
		const ariaLabels = $$('li[aria-label], span[aria-label]').map(el => el.getAttribute('aria-label')).filter(Boolean).slice(0, 20);
		// Inspect __NEXT_DATA__ for coordinate paths
		let nextDataCoords = null;
		try {
			const nd = document.getElementById('__NEXT_DATA__');
			if (nd) {
				const d = JSON.parse(nd.textContent);
				const findCoords = (obj, path, depth) => {
					if (depth > 12 || !obj || typeof obj !== 'object') return;
					for (const k of Object.keys(obj)) {
						if ((k === 'lat' || k === 'latitude') && typeof obj[k] === 'number' && Math.abs(obj[k]) > 0.1 && Math.abs(obj[k]) < 90) {
							const lngKey = k === 'lat' ? 'lng' : 'longitude';
							if (typeof obj[lngKey] === 'number') {
								nextDataCoords = nextDataCoords || {path: path+'.'+k, lat: obj[k], lng: obj[lngKey]};
							}
						}
						findCoords(obj[k], path+'.'+k, depth+1);
					}
				};
				findCoords(d, 'root', 0);
			}
		} catch(e) { nextDataCoords = {error: String(e)}; }
		// JSON-LD structured data (schema.org GeoCoordinates)
		let jsonLdCoords = null;
		try {
			const scripts = Array.from(document.querySelectorAll('script[type="application/ld+json"]'));
			for (const s of scripts) {
				const d = JSON.parse(s.textContent);
				const geo = d?.geo || d?.['@graph']?.find?.(n => n?.geo)?.geo;
				if (geo?.latitude) {
					jsonLdCoords = {lat: parseFloat(geo.latitude), lng: parseFloat(geo.longitude)};
					break;
				}
			}
		} catch(e) { jsonLdCoords = {error: String(e)}; }
		// Inspect LOCATION_DEFAULT element's HTML for map data attributes / static map img URLs
		let locationHtml = '';
		try {
			const locEl = document.querySelector('[data-section-id="LOCATION_DEFAULT"]');
			if (locEl) {
				// Look for any static map images (Google Static Maps embeds lat/lng in the URL)
				const staticMap = locEl.querySelector('img[src*="maps.googleapis.com"], img[src*="maps.google.com"], img[src*="staticmap"]');
				if (staticMap) locationHtml = 'staticmap:' + staticMap.src;
				// Look for elements with lat/lng data attributes
				const mapEl = locEl.querySelector('[data-lat], [data-lng], [data-latlng], [data-center], [data-location]');
				if (mapEl) locationHtml += ' attrs:' + JSON.stringify(mapEl.dataset);
				// Sample outer HTML for manual inspection
				if (!locationHtml) locationHtml = locEl.outerHTML.substring(0, 1500);
			}
		} catch(e) { locationHtml = 'error:' + String(e); }
		// Search all inline scripts for lat/lng coordinate patterns
		let inlineScriptCoords = null;
		try {
			const coordRe = /"lat(?:itude)?"\s*:\s*(-?\d{1,3}\.\d{3,})/;
			const lngRe   = /"l(?:ng|ongitude)"\s*:\s*(-?\d{1,4}\.\d{3,})/;
			for (const s of document.querySelectorAll('script:not([src])')) {
				const text = s.textContent;
				const lm = coordRe.exec(text);
				if (lm) {
					const lng2 = lngRe.exec(text);
					inlineScriptCoords = {lat: parseFloat(lm[1]), lng: lng2 ? parseFloat(lng2[1]) : 0, preview: text.substring(Math.max(0, lm.index-30), lm.index+60)};
					break;
				}
			}
		} catch(e) { inlineScriptCoords = {error: String(e)}; }
		// Check known Airbnb global variables
		let airbnbGlobals = {};
		for (const k of ['__airbnb_data__', 'airbnbBootstrapData', '__AIRBNB_DATA__', 'anoa', 'bootstrapData', '__STATE__']) {
			if (window[k] !== undefined) airbnbGlobals[k] = typeof window[k];
		}
		return JSON.stringify({
			title,
			photo_count: photos.length,
			hosting_photo_count: photos.filter(u => u.includes('/pictures/hosting/')).length,
			photos_sample: photos.slice(0, 3),
			section_ids: sectionIds,
			section_texts: sectionTexts,
			aria_labels: ariaLabels,
			next_data_coords: nextDataCoords,
			json_ld_coords: jsonLdCoords,
			location_html_sample: locationHtml,
			inline_script_coords: inlineScriptCoords,
			airbnb_globals: airbnbGlobals,
		});
	})()`

	err := chromedp.Run(taskCtx,
		chromedp.ActionFunc(func(ctx context.Context) error {
			_, err := page.AddScriptToEvaluateOnNewDocument(fetchInterceptorScript).Do(ctx)
			return err
		}),
		chromedp.Navigate(rawURL),
		chromedp.WaitVisible(`h1`, chromedp.ByQuery),
		chromedp.Sleep(4*time.Second),
		// Click gallery button to reveal all photos (same as FetchRawData)
		chromedp.Evaluate(`(() => {
			const btn = [...document.querySelectorAll('button')].find(b =>
				/show all photos/i.test(b.textContent?.trim())
			);
			if (btn) btn.click();
		})()`, nil),
		chromedp.Sleep(5*time.Second),
		chromedp.Title(&pageTitle),
		chromedp.Location(&currentURL),
		chromedp.Evaluate(`JSON.stringify(window.__captures || {})`, &capturedJSON),
		chromedp.Evaluate(sectionsJS, &sectionsSummaryJSON),
		chromedp.Evaluate(pricingJS, &pricingSummaryJSON),
		chromedp.Evaluate(domInspectJS, &domSummaryJSON),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to load page: %w", err)
	}

	var captures map[string]interface{}
	json.Unmarshal([]byte(capturedJSON), &captures)

	apiURLs := make([]string, 0, len(captures))
	structure := make(map[string]interface{}, len(captures))
	for apiURL, payload := range captures {
		apiURLs = append(apiURLs, apiURL)
		structure[apiURL] = summarizeStructure(payload, 5)
	}

	var sectionsSummary, pricingSummary, domSummary interface{}
	json.Unmarshal([]byte(sectionsSummaryJSON), &sectionsSummary)
	json.Unmarshal([]byte(pricingSummaryJSON), &pricingSummary)
	json.Unmarshal([]byte(domSummaryJSON), &domSummary)

	return &DebugInfo{
		PageTitle:       pageTitle,
		CurrentURL:      currentURL,
		CapturedURLs:    apiURLs,
		CaptureCount:    len(captures),
		Structure:       structure,
		SectionsSummary: sectionsSummary,
		PricingSummary:  pricingSummary,
		DOMSummary:      domSummary,
	}, nil
}

// fetchInterceptorScript is injected before page navigation. It wraps fetch so
// every response to an Airbnb internal API URL is stashed in window.__captures.
// fetchInterceptorScript captures every /api/v3/ response as an array so that
// multiple calls to the same operation (e.g. two StaysPdpSections requests)
// are all preserved rather than the last one overwriting the first.
const fetchInterceptorScript = `
(function() {
  window.__captures = {};
  const _orig = window.fetch;
  window.fetch = async function(...args) {
    const resp = await _orig.apply(this, args);
    try {
      const url = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url ? args[0].url : '');
      if (url && (url.includes('/api/v3/') || url.includes('airbnb.com/api/'))) {
        resp.clone().json().then(function(d) {
          if (!window.__captures[url]) window.__captures[url] = [];
          window.__captures[url].push(d);
        }).catch(function(){});
      }
    } catch(e) {}
    return resp;
  };
  Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
})();
`

// domExtractionJS scrapes listing content from the rendered DOM.
// Airbnb SSR's title, photos, description, and overview into the initial HTML
// rather than fetching them client-side, so we read them from the DOM.
const domExtractionJS = `(() => {
  const $  = sel => document.querySelector(sel);
  const $$ = sel => Array.from(document.querySelectorAll(sel));
  const seen = new Set();
  const photos = $$('img[src*="muscache.com"]')
    .map(img => ({url: img.src, caption: img.alt || ''}))
    .filter(p => p.url
      && p.url.includes('/pictures/hosting/')
      && !seen.has(p.url)
      && seen.add(p.url));
  const sectionMap = {};
  $$('[data-section-id]').forEach(el => {
    const id = el.getAttribute('data-section-id');
    if (id) sectionMap[id] = el.innerText?.trim()?.substring(0, 3000) || '';
  });
  // Host avatar: find the profile image in the host section
  const hostSection = $('[data-section-id="HOST_OVERVIEW_DEFAULT"]') || $('[data-section-id="MEET_YOUR_HOST"]');
  const hostAvatar = hostSection ? (hostSection.querySelector('img[src*="muscache.com"]') || {}).src || '' : '';
  // Coordinates: scan inline <script> tags for "latitude"/"longitude" fields.
  // Airbnb embeds coordinates in a JSON-LD or boot-data script in the SSR'd HTML.
  let lat = 0, lng = 0;
  try {
    const latRe = /"lat(?:itude)?"\s*:\s*(-?\d{1,3}\.\d{3,})/;
    const lngRe = /"l(?:ng|ongitude)"\s*:\s*(-?\d{1,4}\.\d{3,})/;
    for (const s of document.querySelectorAll('script:not([src])')) {
      const text = s.textContent;
      const lm = latRe.exec(text);
      if (lm) {
        const ll = parseFloat(lm[1]);
        if (ll < -90 || ll > 90) continue; // sanity check: must be a latitude
        const um = lngRe.exec(text);
        if (um) { lat = ll; lng = parseFloat(um[1]); break; }
      }
    }
  } catch(e) {}
  return JSON.stringify({
    title:      ($('h1') || {}).innerText?.trim() || '',
    photos:     photos.slice(0, 100),
    host_avatar: hostAvatar,
    sectionMap,
    lat,
    lng,
  });
})()`

// FetchRawData loads the page with two strategies:
//  1. fetch() interceptor → captures API responses (pricing, booking data)
//  2. DOM extraction JS  → scrapes SSR'd listing content (title, photos, overview)
//
// Returns a map of URL → []response plus a special "__dom__" key.
func (s *AirbnbService) FetchRawData(rawURL string) (map[string]interface{}, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Second)
	defer cancel()

	taskCtx, taskCancel := s.newContext(ctx)
	defer taskCancel()

	var capturedJSON, domJSON string
	err := chromedp.Run(taskCtx,
		chromedp.ActionFunc(func(ctx context.Context) error {
			_, err := page.AddScriptToEvaluateOnNewDocument(fetchInterceptorScript).Do(ctx)
			return err
		}),
		chromedp.Navigate(rawURL),
		chromedp.WaitVisible(`h1`, chromedp.ByQuery),
		chromedp.Sleep(4*time.Second),
		// Best-effort: click "Show all photos" via JS so we never block if absent.
		// The button has no data-testid, so we match by text content.
		chromedp.Evaluate(`(() => {
			const btn = [...document.querySelectorAll('button')].find(b =>
				/show all photos/i.test(b.textContent?.trim())
			);
			if (btn) btn.click();
		})()`, nil),
		chromedp.Sleep(5*time.Second),
		// Scroll body and all scrollable containers to trigger lazy-loading of gallery photos.
		// Airbnb's gallery uses a React portal — photos render outside [role="dialog"] in the DOM.
		chromedp.Evaluate(`(() => {
			window.scrollTo(0, 999999);
			document.documentElement.scrollTop = 999999;
			Array.from(document.querySelectorAll('*')).forEach(el => {
				if (el.scrollHeight > el.clientHeight + 200 && el.scrollHeight > 1000) {
					el.scrollTop = el.scrollHeight;
				}
			});
		})()`, nil),
		chromedp.Sleep(3*time.Second),
		chromedp.Evaluate(`JSON.stringify(window.__captures || {})`, &capturedJSON),
		chromedp.Evaluate(domExtractionJS, &domJSON),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to load Airbnb listing: %w", err)
	}

	var captures map[string]interface{}
	if err := json.Unmarshal([]byte(capturedJSON), &captures); err != nil {
		return nil, fmt.Errorf("failed to parse captured data: %w", err)
	}
	if captures == nil {
		captures = map[string]interface{}{}
	}
	var domData interface{}
	json.Unmarshal([]byte(domJSON), &domData)
	captures["__dom__"] = []interface{}{domData}
	return captures, nil
}

func (s *AirbnbService) ParseListing(rawURL string) (*AirbnbListing, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}
	q := parsed.Query()
	checkIn := q.Get("check_in")
	checkOut := q.Get("check_out")
	listingID := extractListingID(rawURL)

	data, err := s.FetchRawData(rawURL)
	if err != nil {
		return nil, err
	}

	listing := s.buildListing(rawURL, listingID, checkIn, checkOut, data)
	return listing, nil
}

// allCaptureSections returns every section from all StaysPdpSections responses.
// Airbnb uses two different response paths depending on the page version.
func allCaptureSections(captures map[string]interface{}) []interface{} {
	var all []interface{}
	for u, val := range captures {
		if !strings.Contains(u, "StaysPdpSections") {
			continue
		}
		for _, resp := range toSlice(val) {
			ss := navSlice(resp, "data", "presentation", "stayProductDetailPage", "sections", "sections")
			if len(ss) == 0 {
				ss = navSlice(resp, "data", "node", "pdpPresentation", "sections", "sections")
			}
			all = append(all, ss...)
		}
	}
	return all
}

// findSection returns the section map for a given sectionId, or nil.
func findSection(sections []interface{}, id string) map[string]interface{} {
	for _, s := range sections {
		m, ok := s.(map[string]interface{})
		if !ok {
			continue
		}
		if m["sectionId"] == id {
			sec, _ := m["section"].(map[string]interface{})
			return sec
		}
	}
	return nil
}

// domData returns the DOM-scraped data map injected under "__dom__".
func domData(captures map[string]interface{}) map[string]interface{} {
	entries := toSlice(captures["__dom__"])
	if len(entries) == 0 {
		return nil
	}
	m, _ := entries[0].(map[string]interface{})
	return m
}

// toSlice safely converts interface{} to []interface{}.
func toSlice(v interface{}) []interface{} {
	s, _ := v.([]interface{})
	return s
}

// buildListing assembles an AirbnbListing from the two data sources:
//   - DOM scrape  → title, photos, description, bedrooms, amenities, etc.
//   - API capture → pricing (BOOK_IT_SIDEBAR.structuredDisplayPrice), maxGuests
func (s *AirbnbService) buildListing(rawURL, listingID, checkIn, checkOut string, captures map[string]interface{}) *AirbnbListing {
	dom := domData(captures)
	sections := allCaptureSections(captures)
	bookIt := findSection(sections, "BOOK_IT_SIDEBAR")
	sectionMap, _ := navGet(dom, "sectionMap").(map[string]interface{})

	// --- Photos from DOM ---
	// Filter out non-listing images (Airbnb platform assets, icons, etc.)
	photos := []AirbnbPhoto{}
	for _, p := range toSlice(navGet(dom, "photos")) {
		pm, _ := p.(map[string]interface{})
		if pm == nil {
			continue
		}
		u, _ := pm["url"].(string)
		cap, _ := pm["caption"].(string)
		if u != "" && strings.Contains(u, "/pictures/hosting/") {
			// Upgrade to higher-res image if possible
			u = strings.ReplaceAll(u, "im_w=720", "im_w=1440")
			photos = append(photos, AirbnbPhoto{URL: u, Caption: cap})
		}
	}

	// --- Overview parsing: "6 guests · 3 bedrooms · 3 beds · 1 bath" ---
	// Airbnb uses OVERVIEW_DEFAULT_V2 in newer deployments, with OVERVIEW_DEFAULT as fallback.
	overviewText := sectionMapText(sectionMap, "OVERVIEW_DEFAULT_V2")
	if overviewText == "" {
		overviewText = sectionMapText(sectionMap, "OVERVIEW_DEFAULT")
	}
	bedrooms := parseCountInText(overviewText, `(\d+)\s+bedroom`)
	beds := parseCountInText(overviewText, `(\d+)\s+bed(?:s)?(?:\s|$|·|,)`)
	bathrooms := parseFloatInText(overviewText, `(\d+(?:\.\d+)?)\s+bath`)
	maxGuests := navInt(bookIt, "maxGuestCapacity")
	if maxGuests == 0 {
		maxGuests = parseCountInText(overviewText, `(\d+)\s+guest`)
	}

	// --- Description & amenities from DOM sections ---
	description := sectionMapText(sectionMap, "DESCRIPTION_DEFAULT")
	amenities := parseAmenities(sectionMapText(sectionMap, "AMENITIES_DEFAULT"))

	// --- Host from DOM section ---
	// Try each section until we get a name — different Airbnb versions use different sections.
	var hostName string
	for _, sec := range []string{"HOST_OVERVIEW_DEFAULT", "MEET_YOUR_HOST", "HOST_PROFILE_DEFAULT"} {
		hostName = parseHostName(sectionMapText(sectionMap, sec))
		if hostName != "" {
			break
		}
	}

	// --- Location from DOM section ---
	locationText := sectionMapText(sectionMap, "LOCATION_DEFAULT")

	// --- Coordinates: GraphQL LOCATION_DEFAULT section first, then __NEXT_DATA__ fallback ---
	locationSection := findSection(sections, "LOCATION_DEFAULT")
	lat := navFloat64(locationSection, "lat")
	lng := navFloat64(locationSection, "lng")
	if lat == 0 {
		lat = navFloat64(locationSection, "mapMarker", "lat")
		lng = navFloat64(locationSection, "mapMarker", "lng")
	}
	if lat == 0 {
		lat = navFloat64(dom, "lat")
		lng = navFloat64(dom, "lng")
	}

	// --- Rating from REVIEWS_DEFAULT section text ---
	reviewText := sectionMapText(sectionMap, "REVIEWS_DEFAULT")
	rating, reviewCount := parseRating(reviewText)

	return &AirbnbListing{
		ListingID:    listingID,
		URL:          stripQuery(rawURL),
		Title:        navStr(dom, "title"),
		Description:  description,
		PropertyType: "",
		RoomType:     "",
		MaxGuests:    maxGuests,
		Bedrooms:     bedrooms,
		Bathrooms:    bathrooms,
		Beds:         beds,
		Location: AirbnbListingLocation{
			City:      parseLocationPart(locationText, 0),
			Country:   parseLocationPart(locationText, -1),
			Latitude:  lat,
			Longitude: lng,
		},
		Host:        AirbnbHost{Name: hostName, Avatar: navStr(dom, "host_avatar")},
		Rating:      rating,
		ReviewCount: reviewCount,
		Photos:      photos,
		Amenities:   amenities,
		CheckIn:     checkIn,
		CheckOut:    checkOut,
		Pricing:     buildPricingFromBookIt(bookIt, checkIn),
	}
}

// --- Section helpers ---

func sectionMapText(sectionMap map[string]interface{}, id string) string {
	if sectionMap == nil {
		return ""
	}
	s, _ := sectionMap[id].(string)
	return s
}

// --- Parsing helpers ---

var (
	priceRe    = regexp.MustCompile(`\$[\d,]+(?:\.\d+)?`)
	nightsRe   = regexp.MustCompile(`(\d+)\s+night`)
	ratingRe   = regexp.MustCompile(`(\d+\.\d+)`)
	reviewsRe  = regexp.MustCompile(`([\d,]+)\s+review`)
	hostNameRe = regexp.MustCompile(`(?i)hosted by (.+)`)
)

func parseCountInText(text, pattern string) int {
	re := regexp.MustCompile(pattern)
	m := re.FindStringSubmatch(text)
	if len(m) < 2 {
		return 0
	}
	n, _ := strconv.Atoi(m[1])
	return n
}

func parseFloatInText(text, pattern string) float64 {
	re := regexp.MustCompile(pattern)
	m := re.FindStringSubmatch(text)
	if len(m) < 2 {
		return 0
	}
	f, _ := strconv.ParseFloat(m[1], 64)
	return f
}

func parsePriceString(s string) float64 {
	s = strings.TrimSpace(s)
	negative := strings.HasPrefix(s, "-")
	s = strings.TrimPrefix(s, "-")
	s = strings.TrimPrefix(s, "$")
	s = strings.ReplaceAll(s, ",", "")
	f, _ := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if negative {
		return -f
	}
	return f
}

func parseAmenities(text string) []string {
	if text == "" {
		return []string{}
	}
	var out []string
	seen := map[string]bool{}
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || seen[line] || len(line) > 80 {
			continue
		}
		// Skip Airbnb section header and "show all" footer
		lower := strings.ToLower(line)
		if lower == "what this place offers" || strings.HasPrefix(lower, "show all ") {
			continue
		}
		seen[line] = true
		out = append(out, line)
	}
	return out
}

func parseHostName(text string) string {
	m := hostNameRe.FindStringSubmatch(text)
	if len(m) < 2 {
		return ""
	}
	// Take only the first line (avoid multi-line noise)
	name := strings.SplitN(strings.TrimSpace(m[1]), "\n", 2)[0]
	return strings.TrimSpace(name)
}

func parseLocationPart(text string, index int) string {
	if text == "" {
		return ""
	}
	// Find the line that looks like "City, Country" (contains a comma and not a header).
	locationLine := ""
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		lower := strings.ToLower(line)
		// Skip common header phrases
		if strings.HasPrefix(lower, "where you") || strings.HasPrefix(lower, "location") {
			continue
		}
		if strings.Contains(line, ",") {
			locationLine = line
			break
		}
	}
	if locationLine == "" {
		return ""
	}
	parts := strings.Split(locationLine, ",")
	if index < 0 {
		index = len(parts) + index
	}
	if index < 0 || index >= len(parts) {
		return ""
	}
	return strings.TrimSpace(parts[index])
}

func parseRating(text string) (float64, int) {
	rm := ratingRe.FindStringSubmatch(text)
	if len(rm) < 2 {
		return 0, 0
	}
	rating, _ := strconv.ParseFloat(rm[1], 64)
	rcm := reviewsRe.FindStringSubmatch(text)
	if len(rcm) < 2 {
		return rating, 0
	}
	countStr := strings.ReplaceAll(rcm[1], ",", "")
	count, _ := strconv.Atoi(countStr)
	return rating, count
}

// buildPricingFromBookIt parses pricing from BOOK_IT_SIDEBAR.structuredDisplayPrice.
// The prices are display strings like "$508"; we parse them to floats.
func buildPricingFromBookIt(bookIt map[string]interface{}, checkIn string) AirbnbPricing {
	if bookIt == nil || checkIn == "" {
		return AirbnbPricing{}
	}

	sdp := navGet(bookIt, "structuredDisplayPrice")
	if sdp == nil {
		return AirbnbPricing{}
	}

	// Total and nights from primaryLine
	totalStr := navStr(sdp, "primaryLine", "discountedPrice")
	if totalStr == "" {
		totalStr = navStr(sdp, "primaryLine", "price")
	}
	qualifier := navStr(sdp, "primaryLine", "qualifier") // "for 3 nights"
	nights := 0
	if m := nightsRe.FindStringSubmatch(qualifier); len(m) >= 2 {
		nights, _ = strconv.Atoi(m[1])
	}

	// Walk priceDetails line items for nightly rate and fees
	var nightlyRate, cleaningFee, serviceFee float64
	currency := "USD"

	for _, group := range navSlice(sdp, "explanationData", "priceDetails") {
		for _, item := range navSlice(group, "items") {
			desc := strings.ToLower(navStr(item, "description"))
			ps := navStr(item, "priceString")
			amt := parsePriceString(ps)
			switch {
			case strings.Contains(desc, "night") && strings.Contains(desc, "x"):
				// "3 nights x $197.16" → nightly rate
				if nights > 0 && amt > 0 {
					// Round to 2 decimal places to avoid float precision noise
					nightlyRate = math.Round(amt/float64(nights)*100) / 100
				} else if m := priceRe.FindString(desc); m != "" {
					nightlyRate = parsePriceString(m)
				}
			case strings.Contains(desc, "cleaning"):
				cleaningFee = amt
			case strings.Contains(desc, "service") || strings.Contains(desc, "airbnb"):
				serviceFee = amt
			}
		}
	}

	total := parsePriceString(totalStr)

	return AirbnbPricing{
		NightlyRate: nightlyRate,
		Nights:      nights,
		CleaningFee: cleaningFee,
		ServiceFee:  serviceFee,
		Total:       total,
		Currency:    currency,
	}
}

// --- JSON navigation helpers ---
// All return zero values on any miss (wrong type, missing key) instead of panicking.

func navGet(node interface{}, keys ...string) interface{} {
	for _, k := range keys {
		m, ok := node.(map[string]interface{})
		if !ok {
			return nil
		}
		node = m[k]
	}
	return node
}

func navStr(node interface{}, keys ...string) string {
	v := navGet(node, keys...)
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

func navFloat64(node interface{}, keys ...string) float64 {
	v := navGet(node, keys...)
	switch n := v.(type) {
	case float64:
		return n
	case json.Number:
		f, _ := n.Float64()
		return f
	}
	return 0
}

func navInt(node interface{}, keys ...string) int {
	v := navGet(node, keys...)
	switch n := v.(type) {
	case float64:
		return int(n)
	case json.Number:
		i, _ := n.Int64()
		return int(i)
	}
	return 0
}

func navSlice(node interface{}, keys ...string) []interface{} {
	v := navGet(node, keys...)
	if s, ok := v.([]interface{}); ok {
		return s
	}
	return nil
}

// getEnv returns the environment variable value or the fallback.
func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
