package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/mux"
)

// Response represents a standard API response
type Response struct {
	Message string `json:"message"`
	Status  string `json:"status"`
}

// HealthResponse represents a health check response
type HealthResponse struct {
	Status    string    `json:"status"`
	Timestamp time.Time `json:"timestamp"`
	Service   string    `json:"service"`
}

// loggingMiddleware logs incoming requests
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf(
			"%s %s %s %v",
			r.Method,
			r.RequestURI,
			r.RemoteAddr,
			time.Since(start),
		)
	})
}

// corsMiddleware adds CORS headers
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept")
		w.Header().Set("Cross-Origin-Resource-Policy", "cross-origin")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// helloHandler handles the hello world endpoint
func helloHandler(w http.ResponseWriter, r *http.Request) {
	response := Response{
		Message: "Hello, World! Welcome to the Travel Route Planner API!",
		Status:  "success",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// healthHandler handles health check endpoint
func healthHandler(w http.ResponseWriter, r *http.Request) {
	response := HealthResponse{
		Status:    "healthy",
		Timestamp: time.Now(),
		Service:   "travel-route-planner-api",
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}

// optimizeRouteHandler handles route optimization requests
func optimizeRouteHandler(w http.ResponseWriter, r *http.Request) {
	var request RouteRequest

	// Parse JSON request body
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: fmt.Sprintf("Invalid JSON: %v", err),
			Status:  "error",
		})
		return
	}

	// Validate input
	if len(request.Locations) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: "At least one location is required",
			Status:  "error",
		})
		return
	}

	if len(request.Locations) > 50 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: "Maximum 50 locations supported",
			Status:  "error",
		})
		return
	}

	// Validate location data
	for i, location := range request.Locations {
		if location.ID == "" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Location %d missing required 'id' field", i),
				Status:  "error",
			})
			return
		}
		// Only validate coordinates if they are provided (not using place name resolution)
		if location.Latitude != nil && (*location.Latitude < -90 || *location.Latitude > 90) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Location %d has invalid latitude: %f", i, *location.Latitude),
				Status:  "error",
			})
			return
		}
		if location.Longitude != nil && (*location.Longitude < -180 || *location.Longitude > 180) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Location %d has invalid longitude: %f", i, *location.Longitude),
				Status:  "error",
			})
			return
		}
	}

	// Validate start index if provided
	if request.StartIndex != nil {
		if *request.StartIndex < 0 || *request.StartIndex >= len(request.Locations) {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Invalid start_index: %d. Must be between 0 and %d", *request.StartIndex, len(request.Locations)-1),
				Status:  "error",
			})
			return
		}
	}

	// Create optimizer and process request
	optimizer := NewRouteOptimizer(request.Locations)
	result := optimizer.OptimizeRoute(request)

	// Return result
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(result)
}

// optimizeCountriesHandler handles country route optimization requests
func optimizeCountriesHandler(w http.ResponseWriter, r *http.Request) {
	var request CountryRouteRequest

	// Parse JSON request body
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: fmt.Sprintf("Invalid JSON: %v", err),
			Status:  "error",
		})
		return
	}

	// Validate input
	if len(request.Countries) == 0 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: "At least one country is required",
			Status:  "error",
		})
		return
	}

	if len(request.Countries) > 20 {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: "Maximum 20 countries supported",
			Status:  "error",
		})
		return
	}

	// Validate country data
	for i, country := range request.Countries {
		if country.Code == "" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Country %d missing required 'code' field", i),
				Status:  "error",
			})
			return
		}
		if country.Name == "" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Country %d missing required 'name' field", i),
				Status:  "error",
			})
			return
		}
		if country.Latitude < -90 || country.Latitude > 90 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Country %d has invalid latitude: %f", i, country.Latitude),
				Status:  "error",
			})
			return
		}
		if country.Longitude < -180 || country.Longitude > 180 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Country %d has invalid longitude: %f", i, country.Longitude),
				Status:  "error",
			})
			return
		}
		if country.MinStayDays <= 0 {
			// Set default minimum stay
			request.Countries[i].MinStayDays = 3
		}
	}

	// Validate optimization focus
	validOptimizations := map[string]bool{
		"distance": true,
		"season":   true,
		"balanced": true,
		"":         true, // Empty defaults to balanced
	}
	if !validOptimizations[strings.ToLower(request.OptimizeFor)] {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(Response{
			Message: "optimize_for must be one of: 'distance', 'season', 'balanced'",
			Status:  "error",
		})
		return
	}

	// Validate start country if provided
	if request.StartCountry != nil {
		found := false
		for _, country := range request.Countries {
			if country.Code == *request.StartCountry {
				found = true
				break
			}
		}
		if !found {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Start country '%s' not found in countries list", *request.StartCountry),
				Status:  "error",
			})
			return
		}
	}

	// Create optimizer and process request
	optimizer := NewCountryOptimizer(request.Countries)
	result := optimizer.optimizeCountryRoute(request)

	// Return result
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(result)
}

// placesSearchHandler handles place search requests
func placesSearchHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	query := r.URL.Query().Get("q")
	if query == "" {
		http.Error(w, "Missing query parameter 'q'", http.StatusBadRequest)
		return
	}

	placesService := NewGooglePlacesService()
	results, err := placesService.SearchPlaces(query)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to search places: %v", err), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"results": results,
		"status":  "success",
	})
}

// placesAutocompleteHandler handles place autocomplete requests
func placesAutocompleteHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	input := r.URL.Query().Get("input")
	if input == "" {
		http.Error(w, "Missing query parameter 'input'", http.StatusBadRequest)
		return
	}

	placesService := NewGooglePlacesService()
	results, err := placesService.GetPlaceAutocomplete(input)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get autocomplete: %v", err), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"predictions": results,
		"status":      "success",
	})
}

// placesDetailsHandler handles place details requests
func placesDetailsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	placeID := r.URL.Query().Get("place_id")
	if placeID == "" {
		http.Error(w, "Missing query parameter 'place_id'", http.StatusBadRequest)
		return
	}

	placesService := NewGooglePlacesService()
	result, err := placesService.GetPlaceDetails(placeID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Failed to get place details: %v", err), http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(map[string]interface{}{
		"result": result,
		"status": "success",
	})
}

func main() {
	// Create a new router
	router := mux.NewRouter()

	// Apply middleware
	router.Use(loggingMiddleware)
	router.Use(corsMiddleware)

	// Define routes
	router.HandleFunc("/", helloHandler).Methods("GET")
	router.HandleFunc("/hello", helloHandler).Methods("GET")
	router.HandleFunc("/health", healthHandler).Methods("GET")

	// API versioning
	api := router.PathPrefix("/api/v1").Subrouter()
	api.HandleFunc("/hello", helloHandler).Methods("GET")
	api.HandleFunc("/health", healthHandler).Methods("GET")
	api.HandleFunc("/optimize-route", optimizeRouteHandler).Methods("POST")
	api.HandleFunc("/optimize-countries", optimizeCountriesHandler).Methods("POST")
	api.HandleFunc("/places/search", placesSearchHandler).Methods("GET")
	api.HandleFunc("/places/autocomplete", placesAutocompleteHandler).Methods("GET")
	api.HandleFunc("/places/details", placesDetailsHandler).Methods("GET")
	api.HandleFunc("/plan", planHandler).Methods("POST")

	// Server configuration
	port := "8080"
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 0,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("Starting Travel Route Planner API server on port %s", port)
	log.Printf("Available endpoints:")
	log.Printf("  GET /                        - Hello World")
	log.Printf("  GET /hello                   - Hello World")
	log.Printf("  GET /health                  - Health Check")
	log.Printf("  GET /api/v1/hello            - Hello World (v1)")
	log.Printf("  GET /api/v1/health           - Health Check (v1)")
	log.Printf("  POST /api/v1/optimize-route     - Route Optimization")
	log.Printf("  POST /api/v1/optimize-countries - Country Route Optimization")
	log.Printf("  GET  /api/v1/places/search      - Search Places")
	log.Printf("  GET  /api/v1/places/autocomplete - Place Autocomplete")
	log.Printf("  GET  /api/v1/places/details     - Place Details")

	if err := server.ListenAndServe(); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
