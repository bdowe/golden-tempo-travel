package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
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
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

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
		if location.Latitude < -90 || location.Latitude > 90 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Location %d has invalid latitude: %f", i, location.Latitude),
				Status:  "error",
			})
			return
		}
		if location.Longitude < -180 || location.Longitude > 180 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			json.NewEncoder(w).Encode(Response{
				Message: fmt.Sprintf("Location %d has invalid longitude: %f", i, location.Longitude),
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

	// Server configuration
	port := "8080"
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	log.Printf("Starting Travel Route Planner API server on port %s", port)
	log.Printf("Available endpoints:")
	log.Printf("  GET /                     - Hello World")
	log.Printf("  GET /hello                - Hello World")
	log.Printf("  GET /health               - Health Check")
	log.Printf("  GET /api/v1/hello         - Hello World (v1)")
	log.Printf("  GET /api/v1/health        - Health Check (v1)")
	log.Printf("  POST /api/v1/optimize-route - Route Optimization")

	if err := server.ListenAndServe(); err != nil {
		log.Fatal("Server failed to start:", err)
	}
}
