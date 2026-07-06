package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

// GooglePlacesService handles Google Places API interactions
type GooglePlacesService struct {
	APIKey string
	Client *http.Client

	// Every Google call is billable; identical lookups within the TTL are
	// served from memory. Autocomplete/details cache long (place data is
	// stable), text search shorter (result sets shift more).
	searchCache       *ttlCache[[]PlaceSearchResult]
	autocompleteCache *ttlCache[[]PlaceAutocompleteResult]
	detailsCache      *ttlCache[*PlaceDetailsResult]
}

// PlaceSearchResult represents a place from Google Places API
type PlaceSearchResult struct {
	PlaceID    string   `json:"place_id"`
	Name       string   `json:"name"`
	Address    string   `json:"formatted_address"`
	Latitude   float64  `json:"lat"`
	Longitude  float64  `json:"lng"`
	Types      []string `json:"types"`
	Rating     *float64 `json:"rating,omitempty"`
	PriceLevel *int     `json:"price_level,omitempty"`
}

// PlaceAutocompleteResult represents autocomplete suggestions
type PlaceAutocompleteResult struct {
	PlaceID     string   `json:"place_id"`
	Description string   `json:"description"`
	Types       []string `json:"types"`
}

// PlaceDetailsResult represents detailed place information
type PlaceDetailsResult struct {
	PlaceID      string              `json:"place_id"`
	Name         string              `json:"name"`
	Address      string              `json:"formatted_address"`
	Latitude     float64             `json:"lat"`
	Longitude    float64             `json:"lng"`
	Types        []string            `json:"types"`
	Rating       *float64            `json:"rating,omitempty"`
	PriceLevel   *int                `json:"price_level,omitempty"`
	OpeningHours *GoogleOpeningHours `json:"opening_hours,omitempty"`
	Website      *string             `json:"website,omitempty"`
	PhoneNumber  *string             `json:"formatted_phone_number,omitempty"`
}

// GoogleOpeningHours represents Google's opening hours format
type GoogleOpeningHours struct {
	OpenNow     bool     `json:"open_now"`
	WeekdayText []string `json:"weekday_text"`
}

// NewGooglePlacesService creates a new Google Places service
func NewGooglePlacesService() *GooglePlacesService {
	apiKey := os.Getenv("GOOGLE_PLACES_API_KEY")
	if apiKey == "" {
		fmt.Println("Warning: GOOGLE_PLACES_API_KEY environment variable not set")
	}

	return &GooglePlacesService{
		APIKey:            apiKey,
		Client:            &http.Client{},
		searchCache:       newTTLCache[[]PlaceSearchResult](1*time.Hour, 2000),
		autocompleteCache: newTTLCache[[]PlaceAutocompleteResult](24*time.Hour, 5000),
		detailsCache:      newTTLCache[*PlaceDetailsResult](24*time.Hour, 5000),
	}
}

// placesService is a process-wide singleton reused across requests, matching
// duffelService/eventsService/weatherService. Constructing it once is what
// makes the TTL caches above effective — a per-request instance would discard
// them and re-bill Google on every call. A missing GOOGLE_PLACES_API_KEY stays
// a soft failure (one boot-time warning; each method returns a clear error),
// so degraded mode keeps working.
var placesService = NewGooglePlacesService()

// SearchPlaces searches for places by text query
func (gps *GooglePlacesService) SearchPlaces(query string) ([]PlaceSearchResult, error) {
	if gps.APIKey == "" {
		return nil, fmt.Errorf("Google Places API key not configured")
	}

	cacheKey := strings.ToLower(strings.TrimSpace(query))
	if cached, ok := gps.searchCache.get(cacheKey); ok {
		return cached, nil
	}

	// Use Text Search API
	baseURL := "https://maps.googleapis.com/maps/api/place/textsearch/json"
	params := url.Values{}
	params.Add("query", query)
	params.Add("key", gps.APIKey)

	resp, err := gps.Client.Get(baseURL + "?" + params.Encode())
	if err != nil {
		return nil, fmt.Errorf("failed to search places: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var result struct {
		Results []struct {
			PlaceID          string `json:"place_id"`
			Name             string `json:"name"`
			FormattedAddress string `json:"formatted_address"`
			Geometry         struct {
				Location struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"location"`
			} `json:"geometry"`
			Types      []string `json:"types"`
			Rating     *float64 `json:"rating"`
			PriceLevel *int     `json:"price_level"`
		} `json:"results"`
		Status string `json:"status"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if result.Status != "OK" {
		return nil, fmt.Errorf("Google Places API error: %s", result.Status)
	}

	places := make([]PlaceSearchResult, len(result.Results))
	for i, place := range result.Results {
		places[i] = PlaceSearchResult{
			PlaceID:    place.PlaceID,
			Name:       place.Name,
			Address:    place.FormattedAddress,
			Latitude:   place.Geometry.Location.Lat,
			Longitude:  place.Geometry.Location.Lng,
			Types:      place.Types,
			Rating:     place.Rating,
			PriceLevel: place.PriceLevel,
		}
	}

	gps.searchCache.set(cacheKey, places)
	return places, nil
}

// GetPlaceAutocomplete gets autocomplete suggestions for a query
func (gps *GooglePlacesService) GetPlaceAutocomplete(input string) ([]PlaceAutocompleteResult, error) {
	if gps.APIKey == "" {
		return nil, fmt.Errorf("Google Places API key not configured")
	}

	cacheKey := strings.ToLower(strings.TrimSpace(input))
	if cached, ok := gps.autocompleteCache.get(cacheKey); ok {
		return cached, nil
	}

	baseURL := "https://maps.googleapis.com/maps/api/place/autocomplete/json"
	params := url.Values{}
	params.Add("input", input)
	params.Add("key", gps.APIKey)

	resp, err := gps.Client.Get(baseURL + "?" + params.Encode())
	if err != nil {
		return nil, fmt.Errorf("failed to get autocomplete: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var result struct {
		Predictions []struct {
			PlaceID     string   `json:"place_id"`
			Description string   `json:"description"`
			Types       []string `json:"types"`
		} `json:"predictions"`
		Status string `json:"status"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if result.Status != "OK" {
		return nil, fmt.Errorf("Google Places API error: %s", result.Status)
	}

	suggestions := make([]PlaceAutocompleteResult, len(result.Predictions))
	for i, pred := range result.Predictions {
		suggestions[i] = PlaceAutocompleteResult{
			PlaceID:     pred.PlaceID,
			Description: pred.Description,
			Types:       pred.Types,
		}
	}

	gps.autocompleteCache.set(cacheKey, suggestions)
	return suggestions, nil
}

// GetPlaceDetails gets detailed information about a place by Place ID
func (gps *GooglePlacesService) GetPlaceDetails(placeID string) (*PlaceDetailsResult, error) {
	if gps.APIKey == "" {
		return nil, fmt.Errorf("Google Places API key not configured")
	}

	if cached, ok := gps.detailsCache.get(placeID); ok {
		return cached, nil
	}

	baseURL := "https://maps.googleapis.com/maps/api/place/details/json"
	params := url.Values{}
	params.Add("place_id", placeID)
	params.Add("fields", "place_id,name,formatted_address,geometry,types,rating,price_level,opening_hours,website,formatted_phone_number")
	params.Add("key", gps.APIKey)

	resp, err := gps.Client.Get(baseURL + "?" + params.Encode())
	if err != nil {
		return nil, fmt.Errorf("failed to get place details: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	var result struct {
		Result struct {
			PlaceID          string `json:"place_id"`
			Name             string `json:"name"`
			FormattedAddress string `json:"formatted_address"`
			Geometry         struct {
				Location struct {
					Lat float64 `json:"lat"`
					Lng float64 `json:"lng"`
				} `json:"location"`
			} `json:"geometry"`
			Types                []string            `json:"types"`
			Rating               *float64            `json:"rating"`
			PriceLevel           *int                `json:"price_level"`
			OpeningHours         *GoogleOpeningHours `json:"opening_hours"`
			Website              *string             `json:"website"`
			FormattedPhoneNumber *string             `json:"formatted_phone_number"`
		} `json:"result"`
		Status string `json:"status"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if result.Status != "OK" {
		return nil, fmt.Errorf("Google Places API error: %s", result.Status)
	}

	place := &PlaceDetailsResult{
		PlaceID:      result.Result.PlaceID,
		Name:         result.Result.Name,
		Address:      result.Result.FormattedAddress,
		Latitude:     result.Result.Geometry.Location.Lat,
		Longitude:    result.Result.Geometry.Location.Lng,
		Types:        result.Result.Types,
		Rating:       result.Result.Rating,
		PriceLevel:   result.Result.PriceLevel,
		OpeningHours: result.Result.OpeningHours,
		Website:      result.Result.Website,
		PhoneNumber:  result.Result.FormattedPhoneNumber,
	}

	gps.detailsCache.set(placeID, place)
	return place, nil
}

// ConvertGoogleHoursToOperatingHours converts Google's opening hours to our format
func ConvertGoogleHoursToOperatingHours(googleHours *GoogleOpeningHours) *OperatingHours {
	if googleHours == nil || len(googleHours.WeekdayText) == 0 {
		return nil
	}

	hours := &OperatingHours{}

	// Google returns weekday_text as ["Monday: 9:00 AM – 5:00 PM", ...]
	for _, dayText := range googleHours.WeekdayText {
		parts := strings.SplitN(dayText, ": ", 2)
		if len(parts) != 2 {
			continue
		}

		day := strings.ToLower(parts[0])
		timeRange := parts[1]

		// Convert "9:00 AM – 5:00 PM" to "09:00-17:00"
		hoursStr := convertGoogleTimeRange(timeRange)

		switch day {
		case "monday":
			hours.Monday = hoursStr
		case "tuesday":
			hours.Tuesday = hoursStr
		case "wednesday":
			hours.Wednesday = hoursStr
		case "thursday":
			hours.Thursday = hoursStr
		case "friday":
			hours.Friday = hoursStr
		case "saturday":
			hours.Saturday = hoursStr
		case "sunday":
			hours.Sunday = hoursStr
		}
	}

	return hours
}

// convertGoogleTimeRange converts "9:00 AM – 5:00 PM" to "09:00-17:00"
func convertGoogleTimeRange(timeRange string) string {
	if strings.Contains(strings.ToLower(timeRange), "closed") {
		return "closed"
	}

	// Simple conversion - this could be more robust
	timeRange = strings.ReplaceAll(timeRange, "–", "-")
	timeRange = strings.ReplaceAll(timeRange, " AM", "")
	timeRange = strings.ReplaceAll(timeRange, " PM", "")

	// This is a simplified conversion - for production, you'd want more robust time parsing
	return timeRange
}

// MapGoogleTypeToCategory maps Google place types to our categories
func MapGoogleTypeToCategory(types []string) string {
	if len(types) == 0 {
		return ""
	}

	// Priority mapping - check most specific types first
	typeMap := map[string]string{
		"restaurant":         "restaurant",
		"food":               "restaurant",
		"meal_takeaway":      "restaurant",
		"cafe":               "coffee_shop",
		"coffee_shop":        "coffee_shop",
		"museum":             "museum",
		"tourist_attraction": "attraction",
		"amusement_park":     "attraction",
		"zoo":                "attraction",
		"park":               "park",
		"shopping_mall":      "shopping",
		"store":              "shopping",
		"hospital":           "medical",
		"pharmacy":           "medical",
		"gas_station":        "gas_station",
		"lodging":            "hotel",
		"movie_theater":      "entertainment",
		"night_club":         "entertainment",
		"gym":                "fitness",
		"church":             "religious",
		"school":             "education",
		"university":         "education",
	}

	for _, gType := range types {
		if category, exists := typeMap[gType]; exists {
			return category
		}
	}

	// Default to the first type if no mapping found
	return types[0]
}
