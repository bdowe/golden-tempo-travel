# Travel Route Planner API

A simple "Hello World" REST API skeleton written in Go, serving as the foundation for a travel route planning application.

## Features

- RESTful API endpoints
- JSON responses
- Logging middleware
- CORS support
- Health check endpoint
- API versioning (v1)
- Graceful server configuration

## Prerequisites

### Local Development
- Go 1.21 or higher
- Git (for cloning and dependency management)

### Docker Development
- Docker
- Docker Compose (optional, for easier development)

## Installation & Running

### Option 1: Docker (Recommended)

#### Using Docker Compose (Easiest)
```bash
# Build and start the application
docker-compose up --build

# Run in background
docker-compose up -d --build

# Stop the application
docker-compose down
```

#### Using Docker directly
```bash
# Build the Docker image
docker build -t travel-route-planner .

# Run the container
docker run -p 8080:8080 travel-route-planner

# Run in background
docker run -d -p 8080:8080 --name travel-api travel-route-planner
```

### Option 2: Local Development

1. Clone or navigate to the project directory:
```bash
cd travel-route-planner
```

2. Download dependencies:
```bash
go mod tidy
```

3. Start the server:
```bash
go run main.go
```

### Verification

The server will start on port 8080. You'll see output similar to:
```
Starting Travel Route Planner API server on port 8080
Available endpoints:
  GET /                  - Hello World
  GET /hello             - Hello World
  GET /health            - Health Check
  GET /api/v1/hello      - Hello World (v1)
  GET /api/v1/health     - Health Check (v1)
```

## API Endpoints

### Root Endpoints

- `GET /` - Returns a hello world message
- `GET /hello` - Returns a hello world message
- `GET /health` - Returns server health status

### Versioned API Endpoints (v1)

- `GET /api/v1/hello` - Returns a hello world message
- `GET /api/v1/health` - Returns server health status
- `POST /api/v1/optimize-route` - Optimizes a route for visiting multiple locations

## Example Responses

### Hello World Endpoint
```bash
curl http://localhost:8081/hello
```

Response:
```json
{
  "message": "Hello, World! Welcome to the Travel Route Planner API!",
  "status": "success"
}
```

### Health Check Endpoint
```bash
curl http://localhost:8081/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:45Z",
  "service": "travel-route-planner-api"
}
```

### Route Optimization Endpoint
```bash
curl -X POST http://localhost:8081/api/v1/optimize-route \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "id": "starbucks",
        "name": "Starbucks Times Square",
        "latitude": 40.7589,
        "longitude": -73.9851,
        "address": "1585 Broadway, New York, NY 10036"
      },
      {
        "id": "central_park",
        "name": "Central Park",
        "latitude": 40.7829,
        "longitude": -73.9654,
        "address": "Central Park, New York, NY"
      },
      {
        "id": "empire_state",
        "name": "Empire State Building",
        "latitude": 40.7484,
        "longitude": -73.9857,
        "address": "350 5th Ave, New York, NY 10118"
      }
    ],
    "start_index": 0,
    "return_to_start": true
  }'
```

Response:
```json
{
  "optimized_route": [
    {
      "id": "starbucks",
      "name": "Starbucks Times Square",
      "latitude": 40.7589,
      "longitude": -73.9851,
      "address": "1585 Broadway, New York, NY 10036"
    },
    {
      "id": "empire_state",
      "name": "Empire State Building",
      "latitude": 40.7484,
      "longitude": -73.9857,
      "address": "350 5th Ave, New York, NY 10118"
    },
    {
      "id": "central_park",
      "name": "Central Park",
      "latitude": 40.7829,
      "longitude": -73.9654,
      "address": "Central Park, New York, NY"
    }
  ],
  "total_distance_km": 3.42,
  "total_travel_time_minutes": 6,
  "total_visit_time_minutes": 105,
  "total_trip_time_minutes": 111,
  "location_timings": [
    {
      "location": {
        "id": "starbucks",
        "name": "Starbucks Times Square",
        "latitude": 40.7589,
        "longitude": -73.9851,
        "category": "coffee_shop"
      },
      "visit_duration_minutes": 15,
      "travel_to_next_minutes": 2
    },
    {
      "location": {
        "id": "empire_state",
        "name": "Empire State Building",
        "latitude": 40.7484,
        "longitude": -73.9857,
        "category": "tourist_attraction"
      },
      "visit_duration_minutes": 45,
      "travel_to_next_minutes": 4
    },
    {
      "location": {
        "id": "central_park",
        "name": "Central Park",
        "latitude": 40.7829,
        "longitude": -73.9654,
        "category": "park"
      },
      "visit_duration_minutes": 30,
      "travel_to_next_minutes": 0
    }
  ],
  "location_count": 3,
  "algorithm_used": "nearest-neighbor + 2-opt",
  "original_distance_km": 3.89,
  "improvement_percentage": 12.08,
  "status": "success"
}
```

#### Route Optimization Request Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `locations` | Array | Yes | Array of location objects (max 50) |
| `locations[].id` | String | Yes | Unique identifier for the location |
| `locations[].name` | String | Yes | Human-readable name for the location |
| `locations[].latitude` | Number | Yes | Latitude (-90 to 90) |
| `locations[].longitude` | Number | Yes | Longitude (-180 to 180) |
| `locations[].address` | String | No | Optional address string |
| `locations[].category` | String | No | Location category for visit time estimation |
| `locations[].visit_duration_minutes` | Number | No | Override estimated visit time (minutes) |
| `start_index` | Number | No | Index of starting location (default: 0) |
| `return_to_start` | Boolean | No | Whether to return to starting point (default: false) |

#### Supported Location Categories

| Category | Default Visit Time | Description |
|----------|-------------------|-------------|
| `coffee_shop` | 15 min | Quick coffee stop |
| `restaurant` | 60 min | Full meal |
| `fast_food` | 20 min | Quick meal |
| `museum` | 90 min | Cultural visit |
| `art_gallery` | 75 min | Art viewing |
| `store` | 30 min | Shopping |
| `grocery_store` | 25 min | Grocery shopping |
| `department_store` | 45 min | Larger shopping trip |
| `bank` | 10 min | Banking transaction |
| `atm` | 3 min | Quick cash withdrawal |
| `gas_station` | 5 min | Fuel stop |
| `tourist_attraction` | 45 min | Sightseeing |
| `park` | 30 min | Park visit |
| `beach` | 60 min | Beach time |
| `gym` | 75 min | Workout |
| `hospital` | 45 min | Medical appointment |
| `pharmacy` | 10 min | Prescription pickup |
| `library` | 40 min | Reading/research |
| `unknown` | 20 min | Default fallback |

## Building for Production

### Docker Production Build
```bash
# Build optimized production image
docker build -t travel-route-planner:latest .

# Tag for registry (optional)
docker tag travel-route-planner:latest your-registry.com/travel-route-planner:latest

# Push to registry (optional)
docker push your-registry.com/travel-route-planner:latest
```

### Local Binary Build
```bash
# Build the binary
go build -o travel-route-planner main.go

# Run the binary
./travel-route-planner
```

## Project Structure

```
travel-route-planner/
├── main.go              # Main application file with HTTP server
├── route_optimizer.go   # Route optimization algorithms (2-Opt)
├── go.mod               # Go module definition
├── go.sum               # Go module checksums
├── Dockerfile           # Docker build configuration
├── .dockerignore        # Docker ignore patterns
├── docker-compose.yml   # Docker Compose configuration
├── test_data.json       # Sample test data for API testing
├── test_examples.sh     # Automated test script
└── README.md            # This file
```

## Middleware

The application includes two middleware components:

1. **Logging Middleware**: Logs all incoming requests with method, URI, remote address, and response time
2. **CORS Middleware**: Adds Cross-Origin Resource Sharing headers for frontend integration

## Route Optimization Features

- **Algorithm**: Nearest Neighbor + 2-Opt optimization
- **Capacity**: Supports up to 50 locations efficiently
- **Performance**: Typically optimizes routes in 10-50ms
- **Quality**: Usually within 5-15% of optimal solution
- **Flexibility**: Optional starting point and round-trip options
- **Visit Time Estimation**: Category-based time estimates with custom overrides
- **Detailed Timing**: Separates travel time from visit time for realistic planning
- **Comprehensive Metrics**: Distance, time estimates, and improvement statistics

## Testing

### Quick Test
```bash
# Start the server
docker-compose up --build

# Run automated tests
./test_examples.sh
```

### Manual Testing
```bash
# Simple 3-location test
curl -X POST http://localhost:8081/api/v1/optimize-route \
  -H "Content-Type: application/json" \
  -d @test_data.json
```

## Docker Features

- **Multi-stage build**: Optimized for small production images
- **Security**: Non-root user execution
- **Health checks**: Built-in health monitoring
- **Development ready**: Docker Compose with hot-reload capability
- **Production ready**: Optimized Alpine Linux base image

## Next Steps

This skeleton provides a solid foundation for building a travel route planner API. Consider adding:

- Database integration (PostgreSQL/Redis examples in docker-compose.yml)
- Authentication and authorization
- Route planning algorithms
- User management
- Trip planning endpoints
- Geographic data integration
- Testing framework
- CI/CD pipeline
- Kubernetes deployment manifests
- Environment-specific configurations
