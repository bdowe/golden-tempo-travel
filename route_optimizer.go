package main

import (
	"math"
	"time"
)

// Location represents a geographic location
type Location struct {
	ID                 string  `json:"id"`
	Name               string  `json:"name"`
	Latitude           float64 `json:"latitude"`
	Longitude          float64 `json:"longitude"`
	Address            string  `json:"address,omitempty"`
	Category           string  `json:"category,omitempty"`           // e.g., "coffee_shop", "museum", "restaurant"
	VisitDurationMin   *int    `json:"visit_duration_minutes,omitempty"` // Optional override for visit time
}

// RouteRequest represents the input for route optimization
type RouteRequest struct {
	Locations     []Location `json:"locations"`
	StartIndex    *int       `json:"start_index,omitempty"` // Optional starting point (0-based)
	ReturnToStart bool       `json:"return_to_start"`       // Round trip vs one-way
}

// LocationTiming represents timing information for a specific location
type LocationTiming struct {
	Location           Location `json:"location"`
	ArrivalTime        string   `json:"arrival_time,omitempty"`
	VisitDurationMin   int      `json:"visit_duration_minutes"`
	DepartureTime      string   `json:"departure_time,omitempty"`
	TravelToNextMin    int      `json:"travel_to_next_minutes"`
}

// RouteResponse represents the optimized route result
type RouteResponse struct {
	OptimizedRoute       []Location        `json:"optimized_route"`
	TotalDistanceKm      float64           `json:"total_distance_km"`
	TotalTravelTimeMin   int               `json:"total_travel_time_minutes"`
	TotalVisitTimeMin    int               `json:"total_visit_time_minutes"`
	TotalTripTimeMin     int               `json:"total_trip_time_minutes"`
	LocationTimings      []LocationTiming  `json:"location_timings"`
	Algorithm            string            `json:"algorithm_used"`
	OriginalDistance     float64           `json:"original_distance_km,omitempty"`
	ImprovementPct       float64           `json:"improvement_percentage,omitempty"`
	LocationCount        int               `json:"location_count"`
	Status               string            `json:"status"`
}

// VisitTimeEstimator handles estimation of visit durations based on location categories
type VisitTimeEstimator struct {
	defaultVisitTimes map[string]int
}

// NewVisitTimeEstimator creates a new visit time estimator with default durations
func NewVisitTimeEstimator() *VisitTimeEstimator {
	return &VisitTimeEstimator{
		defaultVisitTimes: map[string]int{
			"coffee_shop":        15, // Quick coffee stop
			"restaurant":         60, // Full meal
			"fast_food":          20, // Quick meal
			"museum":             90, // Cultural visit
			"art_gallery":        75, // Art viewing
			"store":              30, // Shopping
			"grocery_store":      25, // Grocery shopping
			"department_store":   45, // Larger shopping trip
			"bank":               10, // Banking transaction
			"atm":                3,  // Quick cash withdrawal
			"gas_station":        5,  // Fuel stop
			"tourist_attraction": 45, // Sightseeing
			"park":               30, // Park visit
			"beach":              60, // Beach time
			"gym":                75, // Workout
			"hospital":           45, // Medical appointment
			"pharmacy":           10, // Prescription pickup
			"library":            40, // Reading/research
			"school":             60, // Educational visit
			"church":             45, // Religious service
			"hotel":              15, // Check-in/out
			"airport":            90, // Flight processes
			"subway_station":     5,  // Transit stop
			"parking":            2,  // Parking
			"unknown":            20, // Default fallback
		},
	}
}

// EstimateVisitTime calculates expected visit duration for a location
func (vte *VisitTimeEstimator) EstimateVisitTime(location Location) int {
	// Use explicit duration if provided
	if location.VisitDurationMin != nil {
		return *location.VisitDurationMin
	}
	
	// Use category-based estimate
	if duration, exists := vte.defaultVisitTimes[location.Category]; exists {
		return duration
	}
	
	// Fallback to unknown category default
	return vte.defaultVisitTimes["unknown"]
}

// RouteOptimizer handles route optimization logic
type RouteOptimizer struct {
	locations         []Location
	distanceCache     map[string]float64
	visitTimeEstimator *VisitTimeEstimator
}

// NewRouteOptimizer creates a new optimizer instance
func NewRouteOptimizer(locations []Location) *RouteOptimizer {
	return &RouteOptimizer{
		locations:          locations,
		distanceCache:      make(map[string]float64),
		visitTimeEstimator: NewVisitTimeEstimator(),
	}
}

// haversineDistance calculates the distance between two points using the Haversine formula
func (ro *RouteOptimizer) haversineDistance(lat1, lon1, lat2, lon2 float64) float64 {
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

// getDistance returns cached distance or calculates and caches it
func (ro *RouteOptimizer) getDistance(i, j int) float64 {
	if i == j {
		return 0
	}
	
	// Ensure consistent cache key regardless of order
	key := ""
	if i < j {
		key = ro.locations[i].ID + "-" + ro.locations[j].ID
	} else {
		key = ro.locations[j].ID + "-" + ro.locations[i].ID
	}

	if dist, exists := ro.distanceCache[key]; exists {
		return dist
	}

	loc1 := ro.locations[i]
	loc2 := ro.locations[j]
	dist := ro.haversineDistance(loc1.Latitude, loc1.Longitude, loc2.Latitude, loc2.Longitude)
	ro.distanceCache[key] = dist
	return dist
}

// calculateRouteDistance calculates total distance for a given route
func (ro *RouteOptimizer) calculateRouteDistance(route []int, returnToStart bool) float64 {
	if len(route) < 2 {
		return 0
	}

	totalDistance := 0.0
	for i := 0; i < len(route)-1; i++ {
		totalDistance += ro.getDistance(route[i], route[i+1])
	}

	// Add distance back to start if round trip
	if returnToStart && len(route) > 2 {
		totalDistance += ro.getDistance(route[len(route)-1], route[0])
	}

	return totalDistance
}

// nearestNeighborRoute creates initial route using nearest neighbor algorithm
func (ro *RouteOptimizer) nearestNeighborRoute(startIndex int, returnToStart bool) []int {
	n := len(ro.locations)
	if n == 0 {
		return []int{}
	}

	route := make([]int, 0, n)
	visited := make([]bool, n)
	
	current := startIndex
	route = append(route, current)
	visited[current] = true

	// Build route by always going to nearest unvisited location
	for len(route) < n {
		nearest := -1
		minDist := math.Inf(1)

		for i := 0; i < n; i++ {
			if !visited[i] {
				dist := ro.getDistance(current, i)
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

	return route
}

// twoOptSwap performs a 2-opt swap on the route
func (ro *RouteOptimizer) twoOptSwap(route []int, i, k int) []int {
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

// optimizeWith2Opt improves the route using 2-opt algorithm
func (ro *RouteOptimizer) optimizeWith2Opt(initialRoute []int, returnToStart bool, maxIterations int) []int {
	if len(initialRoute) < 4 {
		return initialRoute // 2-opt needs at least 4 locations
	}

	currentRoute := make([]int, len(initialRoute))
	copy(currentRoute, initialRoute)
	bestDistance := ro.calculateRouteDistance(currentRoute, returnToStart)
	
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
				newRoute := ro.twoOptSwap(currentRoute, i, k)
				newDistance := ro.calculateRouteDistance(newRoute, returnToStart)
				
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

// findLocationIndex finds the index of a location by ID in the locations array
func (ro *RouteOptimizer) findLocationIndex(locationID string) int {
	for i, location := range ro.locations {
		if location.ID == locationID {
			return i
		}
	}
	return -1
}

// OptimizeRoute is the main function to optimize a route
func (ro *RouteOptimizer) OptimizeRoute(request RouteRequest) RouteResponse {
	if len(request.Locations) == 0 {
		return RouteResponse{
			Status: "error: no locations provided",
		}
	}

	if len(request.Locations) == 1 {
		return RouteResponse{
			OptimizedRoute:   request.Locations,
			TotalDistanceKm:  0,
			EstimatedTimeMin: 0,
			LocationCount:    1,
			Algorithm:        "single-location",
			Status:           "success",
		}
	}

	// Set up locations and determine start index
	ro.locations = request.Locations
	startIndex := 0
	if request.StartIndex != nil && *request.StartIndex >= 0 && *request.StartIndex < len(request.Locations) {
		startIndex = *request.StartIndex
	}

	// Create initial route using nearest neighbor
	initialRoute := ro.nearestNeighborRoute(startIndex, request.ReturnToStart)
	originalDistance := ro.calculateRouteDistance(initialRoute, request.ReturnToStart)

	// Optimize using 2-opt (limit iterations for performance)
	maxIterations := 100
	if len(request.Locations) > 20 {
		maxIterations = 50 // Reduce iterations for larger problems
	}
	
	optimizedRoute := ro.optimizeWith2Opt(initialRoute, request.ReturnToStart, maxIterations)
	optimizedDistance := ro.calculateRouteDistance(optimizedRoute, request.ReturnToStart)

	// Convert indices back to locations
	result := make([]Location, len(optimizedRoute))
	for i, idx := range optimizedRoute {
		result[i] = request.Locations[idx]
	}

	// Calculate improvement percentage
	improvementPct := 0.0
	if originalDistance > 0 {
		improvementPct = ((originalDistance - optimizedDistance) / originalDistance) * 100
	}

	// Calculate travel time (assuming average speed of 40 km/h in city)
	travelTimeMin := int(math.Ceil(optimizedDistance / 40.0 * 60))

	// Calculate visit times and create detailed timing information
	locationTimings := make([]LocationTiming, len(result))
	totalVisitTime := 0
	
	for i, location := range result {
		visitDuration := ro.visitTimeEstimator.EstimateVisitTime(location)
		totalVisitTime += visitDuration
		
		// Calculate travel time to next location
		travelToNext := 0
		if i < len(result)-1 {
			// Find indices in original locations array
			currentIdx := ro.findLocationIndex(location.ID)
			nextIdx := ro.findLocationIndex(result[i+1].ID)
			if currentIdx != -1 && nextIdx != -1 {
				travelDistance := ro.getDistance(currentIdx, nextIdx)
				travelToNext = int(math.Ceil(travelDistance / 40.0 * 60)) // 40 km/h average
			}
		} else if request.ReturnToStart && len(result) > 1 {
			// Travel time back to start
			currentIdx := ro.findLocationIndex(location.ID)
			startIdx := ro.findLocationIndex(result[0].ID)
			if currentIdx != -1 && startIdx != -1 {
				travelDistance := ro.getDistance(currentIdx, startIdx)
				travelToNext = int(math.Ceil(travelDistance / 40.0 * 60))
			}
		}
		
		locationTimings[i] = LocationTiming{
			Location:         location,
			VisitDurationMin: visitDuration,
			TravelToNextMin:  travelToNext,
		}
	}

	totalTripTime := travelTimeMin + totalVisitTime

	return RouteResponse{
		OptimizedRoute:     result,
		TotalDistanceKm:    math.Round(optimizedDistance*100) / 100,
		TotalTravelTimeMin: travelTimeMin,
		TotalVisitTimeMin:  totalVisitTime,
		TotalTripTimeMin:   totalTripTime,
		LocationTimings:    locationTimings,
		LocationCount:      len(request.Locations),
		Algorithm:          "nearest-neighbor + 2-opt",
		OriginalDistance:   math.Round(originalDistance*100) / 100,
		ImprovementPct:     math.Round(improvementPct*100) / 100,
		Status:             "success",
	}
}
