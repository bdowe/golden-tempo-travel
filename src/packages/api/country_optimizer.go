package main

import (
	"math"
	"strings"
	"time"
)

// Season represents the ideal travel seasons for a country
type Season struct {
	Name        string `json:"name"`        // "spring", "summer", "fall", "winter"
	StartMonth  int    `json:"start_month"` // 1-12
	EndMonth    int    `json:"end_month"`   // 1-12
	Description string `json:"description"` // e.g., "Dry season, perfect weather"
}

// Country represents a country with travel information
type Country struct {
	Code         string   `json:"code"`                   // ISO country code (e.g., "US", "FR")
	Name         string   `json:"name"`                   // Full country name
	Capital      string   `json:"capital"`                // Capital city
	Latitude     float64  `json:"latitude"`               // Country center latitude
	Longitude    float64  `json:"longitude"`              // Country center longitude
	IdealSeasons []Season `json:"ideal_seasons"`          // Best times to visit
	AvoidMonths  []int    `json:"avoid_months,omitempty"` // Months to avoid (1-12)
	MinStayDays  int      `json:"min_stay_days"`          // Minimum recommended stay
	Continent    string   `json:"continent"`              // Continent name
	Timezone     string   `json:"timezone,omitempty"`     // Primary timezone
	Currency     string   `json:"currency,omitempty"`     // Primary currency
}

// CountryRouteRequest represents the input for country route optimization
type CountryRouteRequest struct {
	Countries     []Country `json:"countries"`
	StartCountry  *string   `json:"start_country,omitempty"`      // Country code to start from
	TripStartDate *string   `json:"trip_start_date,omitempty"`    // YYYY-MM-DD format
	TripDuration  *int      `json:"trip_duration_days,omitempty"` // Total trip duration in days
	ReturnToStart bool      `json:"return_to_start"`              // Round trip vs one-way
	OptimizeFor   string    `json:"optimize_for"`                 // "distance", "season", "balanced"
}

// CountryTiming represents timing and seasonal information for a country visit
type CountryTiming struct {
	Country       Country `json:"country"`
	ArrivalDate   string  `json:"arrival_date"`   // YYYY-MM-DD
	DepartureDate string  `json:"departure_date"` // YYYY-MM-DD
	StayDuration  int     `json:"stay_duration_days"`
	Season        string  `json:"season"`              // Current season during visit
	WeatherRating int     `json:"weather_rating"`      // 1-10 rating for travel conditions
	SeasonalNotes string  `json:"seasonal_notes"`      // Description of conditions
	TravelToNext  int     `json:"travel_to_next_days"` // Days to travel to next country
}

// CountryRouteResponse represents the optimized country route result
type CountryRouteResponse struct {
	OptimizedRoute    []Country       `json:"optimized_route"`
	CountryTimings    []CountryTiming `json:"country_timings"`
	TotalDistanceKm   float64         `json:"total_distance_km"`
	TotalTripDays     int             `json:"total_trip_days"`
	TotalTravelDays   int             `json:"total_travel_days"`
	TotalStayDays     int             `json:"total_stay_days"`
	SeasonalScore     float64         `json:"seasonal_score"` // 0-100 overall seasonal optimization
	DistanceScore     float64         `json:"distance_score"` // 0-100 distance optimization
	OverallScore      float64         `json:"overall_score"`  // 0-100 combined score
	Algorithm         string          `json:"algorithm_used"`
	OptimizationFocus string          `json:"optimization_focus"`
	CountryCount      int             `json:"country_count"`
	Status            string          `json:"status"`
}

// CountryOptimizer handles country route optimization
type CountryOptimizer struct {
	countries     []Country
	distanceCache map[string]float64
	seasonalData  map[string][]Season
}

// NewCountryOptimizer creates a new country optimizer instance
func NewCountryOptimizer(countries []Country) *CountryOptimizer {
	optimizer := &CountryOptimizer{
		countries:     countries,
		distanceCache: make(map[string]float64),
		seasonalData:  make(map[string][]Season),
	}

	// Cache seasonal data for quick lookup
	for _, country := range countries {
		optimizer.seasonalData[country.Code] = country.IdealSeasons
	}

	return optimizer
}

// haversineDistance calculates the distance between two points using the Haversine formula
// This uses the exact same implementation as the location optimizer for consistency
func (co *CountryOptimizer) haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
	// Convert to radians
	lat1Rad := lat1 * math.Pi / 180
	lon1Rad := lon1 * math.Pi / 180
	lat2Rad := lat2 * math.Pi / 180
	lon2Rad := lon2 * math.Pi / 180

	// Haversine formula
	dLat := lat2Rad - lat1Rad
	dLon := lon2Rad - lon1Rad
	a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(lat1Rad)*math.Cos(lat2Rad)*math.Sin(dLon/2)*math.Sin(dLon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	// Earth's radius in kilometers
	earthRadius := 6371.0
	return earthRadius * c
}

// getCountryDistance calculates distance between two countries using their center coordinates
func (co *CountryOptimizer) getCountryDistance(country1, country2 Country) float64 {
	if country1.Code == country2.Code {
		return 0
	}

	// Ensure consistent cache key regardless of order
	key := ""
	if country1.Code < country2.Code {
		key = country1.Code + "-" + country2.Code
	} else {
		key = country2.Code + "-" + country1.Code
	}

	// Check cache
	if dist, exists := co.distanceCache[key]; exists {
		return dist
	}

	// Calculate using the same Haversine formula as location optimizer
	distance := co.haversineDistance(country1.Latitude, country1.Longitude, country2.Latitude, country2.Longitude)

	// Cache the result
	co.distanceCache[key] = distance
	return distance
}

// getSeasonalScore calculates how good a month is for visiting a country (0-10)
func (co *CountryOptimizer) getSeasonalScore(country Country, month int) (float64, string, string) {
	if len(country.IdealSeasons) == 0 {
		return 7.0, "unknown", "No seasonal data available" // Default moderate score
	}

	// Check if month is in avoid list
	for _, avoidMonth := range country.AvoidMonths {
		if month == avoidMonth {
			return 2.0, "avoid", "Not recommended travel period"
		}
	}

	bestScore := 0.0
	bestSeason := ""
	bestDescription := ""

	for _, season := range country.IdealSeasons {
		score := 0.0

		// Handle seasons that cross year boundary (e.g., Dec-Feb)
		if season.StartMonth <= season.EndMonth {
			// Normal season (e.g., Jun-Aug)
			if month >= season.StartMonth && month <= season.EndMonth {
				score = 10.0
			}
		} else {
			// Season crosses year boundary (e.g., Dec-Feb)
			if month >= season.StartMonth || month <= season.EndMonth {
				score = 10.0
			}
		}

		// Give partial scores for shoulder months
		if score == 0.0 {
			if season.StartMonth <= season.EndMonth {
				if month == season.StartMonth-1 || month == season.EndMonth+1 {
					score = 6.0 // Shoulder season
				}
			} else {
				if month == season.StartMonth-1 || month == season.EndMonth+1 {
					score = 6.0 // Shoulder season
				}
			}
		}

		if score > bestScore {
			bestScore = score
			bestSeason = season.Name
			bestDescription = season.Description
		}
	}

	if bestScore == 0.0 {
		return 4.0, "off-season", "Off-season period"
	}

	return bestScore, bestSeason, bestDescription
}

// optimizeCountryRoute optimizes the country visiting order
func (co *CountryOptimizer) optimizeCountryRoute(request CountryRouteRequest) CountryRouteResponse {
	if len(request.Countries) == 0 {
		return CountryRouteResponse{
			Status: "error: no countries provided",
		}
	}

	if len(request.Countries) == 1 {
		return co.createSingleCountryResponse(request)
	}

	// Determine optimization strategy
	optimizeFor := strings.ToLower(request.OptimizeFor)
	if optimizeFor == "" {
		optimizeFor = "balanced" // Default
	}

	co.countries = request.Countries

	// Create initial route using nearest neighbor with seasonal weighting
	startIndex := 0
	if request.StartCountry != nil {
		for i, country := range request.Countries {
			if country.Code == *request.StartCountry {
				startIndex = i
				break
			}
		}
	}

	// Parse start date
	startDate := time.Now()
	if request.TripStartDate != nil {
		if parsed, err := time.Parse("2006-01-02", *request.TripStartDate); err == nil {
			startDate = parsed
		}
	}

	// Calculate optimal route
	var optimizedRoute []int
	switch optimizeFor {
	case "distance":
		optimizedRoute = co.optimizeForDistance(startIndex)
	case "season":
		optimizedRoute = co.optimizeForSeason(startIndex, startDate, request.TripDuration)
	default: // "balanced"
		optimizedRoute = co.optimizeBalanced(startIndex, startDate, request.TripDuration)
	}

	// Convert indices to countries
	result := make([]Country, len(optimizedRoute))
	for i, idx := range optimizedRoute {
		result[i] = request.Countries[idx]
	}

	// Calculate trip timing and metrics
	return co.calculateCountryTiming(result, startDate, request)
}

// optimizeForDistance creates route optimized purely for minimum travel distance
func (co *CountryOptimizer) optimizeForDistance(startIndex int) []int {
	n := len(co.countries)
	route := make([]int, 0, n)
	visited := make([]bool, n)

	current := startIndex
	route = append(route, current)
	visited[current] = true

	// Greedy nearest neighbor for distance
	for len(route) < n {
		nearest := -1
		minDist := math.Inf(1)

		for i := 0; i < n; i++ {
			if !visited[i] {
				dist := co.getCountryDistance(co.countries[current], co.countries[i])
				if dist < minDist {
					minDist = dist
					nearest = i
				}
			}
		}

		if nearest == -1 {
			break
		}

		route = append(route, nearest)
		visited[nearest] = true
		current = nearest
	}

	// Apply 2-opt improvement for distance optimization
	maxIterations := 100
	if n > 10 {
		maxIterations = 50 // Reduce iterations for larger country sets
	}

	// For distance optimization, we can use return to start for better optimization
	return co.optimizeWith2Opt(route, true, maxIterations)
}

// optimizeForSeason creates route optimized for ideal travel seasons
func (co *CountryOptimizer) optimizeForSeason(startIndex int, startDate time.Time, tripDuration *int) []int {
	n := len(co.countries)
	route := make([]int, 0, n)
	visited := make([]bool, n)

	current := startIndex
	route = append(route, current)
	visited[current] = true
	currentDate := startDate

	// Add minimum stay time for first country
	currentDate = currentDate.AddDate(0, 0, co.countries[current].MinStayDays)

	for len(route) < n {
		bestCountry := -1
		bestScore := -1.0

		for i := 0; i < n; i++ {
			if !visited[i] {
				// Calculate seasonal score for arrival month
				score, _, _ := co.getSeasonalScore(co.countries[i], int(currentDate.Month()))

				// Add small distance penalty to break ties
				dist := co.getCountryDistance(co.countries[current], co.countries[i])
				distancePenalty := dist / 10000.0 // Small penalty
				adjustedScore := score - distancePenalty

				if adjustedScore > bestScore {
					bestScore = adjustedScore
					bestCountry = i
				}
			}
		}

		if bestCountry == -1 {
			break
		}

		route = append(route, bestCountry)
		visited[bestCountry] = true
		current = bestCountry

		// Add travel time (estimated 1-3 days) and stay time
		travelDays := int(co.getCountryDistance(co.countries[route[len(route)-2]], co.countries[current])/2000) + 1
		if travelDays > 3 {
			travelDays = 3
		}
		currentDate = currentDate.AddDate(0, 0, travelDays+co.countries[current].MinStayDays)
	}

	// Apply limited 2-opt improvement while preserving seasonal priorities
	// Use fewer iterations to avoid disrupting seasonal optimization too much
	maxIterations := 25
	if n > 10 {
		maxIterations = 15
	}

	return co.optimizeWith2Opt(route, false, maxIterations)
}

// optimizeBalanced creates route balancing distance and seasonal factors
func (co *CountryOptimizer) optimizeBalanced(startIndex int, startDate time.Time, tripDuration *int) []int {
	n := len(co.countries)
	route := make([]int, 0, n)
	visited := make([]bool, n)

	current := startIndex
	route = append(route, current)
	visited[current] = true
	currentDate := startDate

	currentDate = currentDate.AddDate(0, 0, co.countries[current].MinStayDays)

	for len(route) < n {
		bestCountry := -1
		bestScore := -1.0

		for i := 0; i < n; i++ {
			if !visited[i] {
				// Seasonal score (0-10)
				seasonalScore, _, _ := co.getSeasonalScore(co.countries[i], int(currentDate.Month()))

				// Distance score (inverted and normalized)
				dist := co.getCountryDistance(co.countries[current], co.countries[i])
				maxDist := 20000.0                               // Rough max distance between any two countries
				distanceScore := (maxDist - dist) / maxDist * 10 // 0-10 scale

				// Balanced score (60% seasonal, 40% distance)
				balancedScore := seasonalScore*0.6 + distanceScore*0.4

				if balancedScore > bestScore {
					bestScore = balancedScore
					bestCountry = i
				}
			}
		}

		if bestCountry == -1 {
			break
		}

		route = append(route, bestCountry)
		visited[bestCountry] = true
		current = bestCountry

		// Update current date
		travelDays := int(co.getCountryDistance(co.countries[route[len(route)-2]], co.countries[current])/2000) + 1
		if travelDays > 3 {
			travelDays = 3
		}
		currentDate = currentDate.AddDate(0, 0, travelDays+co.countries[current].MinStayDays)
	}

	// Apply moderate 2-opt improvement for balanced optimization
	maxIterations := 50
	if n > 10 {
		maxIterations = 30
	}

	return co.optimizeWith2Opt(route, false, maxIterations)
}

// twoOptSwap performs a 2-opt swap on the country route
// This uses the exact same implementation as the location optimizer
func (co *CountryOptimizer) twoOptSwap(route []int, i, k int) []int {
	newRoute := make([]int, len(route))

	// Copy the first part
	copy(newRoute[0:i], route[0:i])

	// Reverse the middle part
	for j := 0; j <= k-i; j++ {
		newRoute[i+j] = route[k-j]
	}

	// Copy the last part
	copy(newRoute[k+1:], route[k+1:])

	return newRoute
}

// calculateCountryRouteDistance calculates total distance for a given country route
func (co *CountryOptimizer) calculateCountryRouteDistance(route []int, returnToStart bool) float64 {
	if len(route) < 2 {
		return 0
	}

	totalDistance := 0.0
	for i := 0; i < len(route)-1; i++ {
		totalDistance += co.getCountryDistance(co.countries[route[i]], co.countries[route[i+1]])
	}

	// Add distance back to start if round trip
	if returnToStart && len(route) > 2 {
		totalDistance += co.getCountryDistance(co.countries[route[len(route)-1]], co.countries[route[0]])
	}

	return totalDistance
}

// optimizeWith2Opt improves the country route using 2-opt algorithm
func (co *CountryOptimizer) optimizeWith2Opt(initialRoute []int, returnToStart bool, maxIterations int) []int {
	if len(initialRoute) < 4 {
		return initialRoute // 2-opt needs at least 4 countries
	}

	currentRoute := make([]int, len(initialRoute))
	copy(currentRoute, initialRoute)
	bestDistance := co.calculateCountryRouteDistance(currentRoute, returnToStart)

	improved := true
	iteration := 0

	for improved && iteration < maxIterations {
		improved = false
		iteration++

		// Try all possible 2-opt swaps
		for i := 1; i < len(currentRoute)-2; i++ {
			for k := i + 1; k < len(currentRoute); k++ {
				// Skip if this would affect the return-to-start constraint
				if returnToStart && k == len(currentRoute)-1 {
					continue
				}

				// Create new route with 2-opt swap
				newRoute := co.twoOptSwap(currentRoute, i, k)
				newDistance := co.calculateCountryRouteDistance(newRoute, returnToStart)

				// If improvement found, accept it
				if newDistance < bestDistance {
					currentRoute = newRoute
					bestDistance = newDistance
					improved = true
				}
			}
		}
	}

	return currentRoute
}

// createSingleCountryResponse handles single country requests
func (co *CountryOptimizer) createSingleCountryResponse(request CountryRouteRequest) CountryRouteResponse {
	country := request.Countries[0]
	startDate := time.Now()
	if request.TripStartDate != nil {
		if parsed, err := time.Parse("2006-01-02", *request.TripStartDate); err == nil {
			startDate = parsed
		}
	}

	score, season, notes := co.getSeasonalScore(country, int(startDate.Month()))

	timing := CountryTiming{
		Country:       country,
		ArrivalDate:   startDate.Format("2006-01-02"),
		DepartureDate: startDate.AddDate(0, 0, country.MinStayDays).Format("2006-01-02"),
		StayDuration:  country.MinStayDays,
		Season:        season,
		WeatherRating: int(score),
		SeasonalNotes: notes,
		TravelToNext:  0,
	}

	return CountryRouteResponse{
		OptimizedRoute:    []Country{country},
		CountryTimings:    []CountryTiming{timing},
		TotalDistanceKm:   0,
		TotalTripDays:     country.MinStayDays,
		TotalTravelDays:   0,
		TotalStayDays:     country.MinStayDays,
		SeasonalScore:     score * 10, // Convert to 0-100 scale
		DistanceScore:     100,        // Perfect distance score for single country
		OverallScore:      score * 10,
		Algorithm:         "single-country",
		OptimizationFocus: request.OptimizeFor,
		CountryCount:      1,
		Status:            "success",
	}
}

// calculateCountryTiming calculates detailed timing and metrics for the route
func (co *CountryOptimizer) calculateCountryTiming(route []Country, startDate time.Time, request CountryRouteRequest) CountryRouteResponse {
	timings := make([]CountryTiming, len(route))
	currentDate := startDate
	totalDistance := 0.0
	totalTravelDays := 0
	totalStayDays := 0
	seasonalScores := make([]float64, len(route))

	for i, country := range route {
		// Calculate stay duration
		stayDays := country.MinStayDays
		if request.TripDuration != nil && len(route) > 1 {
			// Distribute total duration across countries
			avgStay := *request.TripDuration / len(route)
			if avgStay > country.MinStayDays {
				stayDays = avgStay
			}
		}

		// Calculate seasonal info
		score, season, notes := co.getSeasonalScore(country, int(currentDate.Month()))
		seasonalScores[i] = score

		// Calculate travel time to next country
		travelDays := 0
		if i < len(route)-1 {
			dist := co.getCountryDistance(country, route[i+1])
			totalDistance += dist
			travelDays = int(dist/2000) + 1 // Rough estimate: 2000km per day
			if travelDays > 7 {
				travelDays = 7 // Cap at 1 week travel time
			}
		} else if request.ReturnToStart && len(route) > 1 {
			dist := co.getCountryDistance(country, route[0])
			totalDistance += dist
			travelDays = int(dist/2000) + 1
			if travelDays > 7 {
				travelDays = 7
			}
		}

		timings[i] = CountryTiming{
			Country:       country,
			ArrivalDate:   currentDate.Format("2006-01-02"),
			DepartureDate: currentDate.AddDate(0, 0, stayDays).Format("2006-01-02"),
			StayDuration:  stayDays,
			Season:        season,
			WeatherRating: int(score),
			SeasonalNotes: notes,
			TravelToNext:  travelDays,
		}

		totalStayDays += stayDays
		totalTravelDays += travelDays

		// Move to next country
		currentDate = currentDate.AddDate(0, 0, stayDays+travelDays)
	}

	// Calculate scores
	avgSeasonalScore := 0.0
	for _, score := range seasonalScores {
		avgSeasonalScore += score
	}
	avgSeasonalScore = avgSeasonalScore / float64(len(seasonalScores)) * 10 // Convert to 0-100

	// Distance score (lower distance = higher score)
	maxPossibleDistance := float64(len(route)) * 15000.0 // Rough estimate
	distanceScore := math.Max(0, (maxPossibleDistance-totalDistance)/maxPossibleDistance*100)

	// Overall score based on optimization focus
	overallScore := avgSeasonalScore
	switch strings.ToLower(request.OptimizeFor) {
	case "distance":
		overallScore = distanceScore
	case "season":
		overallScore = avgSeasonalScore
	default: // balanced
		overallScore = avgSeasonalScore*0.6 + distanceScore*0.4
	}

	return CountryRouteResponse{
		OptimizedRoute:    route,
		CountryTimings:    timings,
		TotalDistanceKm:   math.Round(totalDistance*100) / 100,
		TotalTripDays:     totalStayDays + totalTravelDays,
		TotalTravelDays:   totalTravelDays,
		TotalStayDays:     totalStayDays,
		SeasonalScore:     math.Round(avgSeasonalScore*100) / 100,
		DistanceScore:     math.Round(distanceScore*100) / 100,
		OverallScore:      math.Round(overallScore*100) / 100,
		Algorithm:         "nearest-neighbor + 2-opt + seasonal-weighting",
		OptimizationFocus: request.OptimizeFor,
		CountryCount:      len(route),
		Status:            "success",
	}
}
