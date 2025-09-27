#!/bin/bash

# Test Examples for Travel Route Planner API
# Make sure the server is running first: go run main.go route_optimizer.go

BASE_URL="http://localhost:8081"  # Updated for docker-compose port
API_BASE="$BASE_URL/api/v1"

echo "🚀 Testing Travel Route Planner API"
echo "=================================="

# Test 1: Health Check
echo "1️⃣  Testing Health Check..."
curl -s "$API_BASE/health" | jq '.'
echo -e "\n"

# Test 2: Simple NYC Tourist Route (5 locations)
echo "2️⃣  Testing NYC Tourist Route (5 locations)..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "id": "starbucks_times_square",
        "name": "Starbucks Times Square",
        "latitude": 40.7589,
        "longitude": -73.9851,
        "address": "1585 Broadway, New York, NY 10036",
        "category": "coffee_shop"
      },
      {
        "id": "central_park",
        "name": "Central Park",
        "latitude": 40.7829,
        "longitude": -73.9654,
        "address": "Central Park, New York, NY",
        "category": "park"
      },
      {
        "id": "empire_state_building",
        "name": "Empire State Building",
        "latitude": 40.7484,
        "longitude": -73.9857,
        "address": "350 5th Ave, New York, NY 10118",
        "category": "tourist_attraction"
      },
      {
        "id": "brooklyn_bridge",
        "name": "Brooklyn Bridge",
        "latitude": 40.7061,
        "longitude": -73.9969,
        "address": "Brooklyn Bridge, New York, NY 10038",
        "category": "tourist_attraction"
      },
      {
        "id": "statue_of_liberty",
        "name": "Statue of Liberty",
        "latitude": 40.6892,
        "longitude": -74.0445,
        "address": "Liberty Island, New York, NY 10004",
        "category": "tourist_attraction"
      }
    ],
    "start_index": 0,
    "return_to_start": true
  }' | jq '.'
echo -e "\n"

# Test 3: Coffee Shop Tour (7 locations, one-way)
echo "3️⃣  Testing Coffee Shop Tour (7 locations, one-way)..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "id": "blue_bottle_tribeca",
        "name": "Blue Bottle Coffee - Tribeca",
        "latitude": 40.7195,
        "longitude": -74.0089,
        "category": "coffee_shop"
      },
      {
        "id": "intelligentsia_high_line",
        "name": "Intelligentsia Coffee - High Line",
        "latitude": 40.7420,
        "longitude": -74.0048,
        "category": "coffee_shop"
      },
      {
        "id": "joe_coffee_waverly",
        "name": "Joe Coffee - Waverly Place",
        "latitude": 40.7323,
        "longitude": -74.0027,
        "category": "coffee_shop"
      },
      {
        "id": "stumptown_ace_hotel",
        "name": "Stumptown Coffee - Ace Hotel",
        "latitude": 40.7451,
        "longitude": -73.9890,
        "category": "coffee_shop"
      },
      {
        "id": "birch_coffee_flatiron",
        "name": "Birch Coffee - Flatiron",
        "latitude": 40.7414,
        "longitude": -73.9896,
        "category": "coffee_shop"
      },
      {
        "id": "la_colombe_soho",
        "name": "La Colombe - SoHo",
        "latitude": 40.7230,
        "longitude": -74.0030,
        "category": "coffee_shop"
      },
      {
        "id": "bluestone_lane_greenwich",
        "name": "Bluestone Lane - Greenwich Village",
        "latitude": 40.7336,
        "longitude": -74.0027,
        "category": "coffee_shop"
      }
    ],
    "start_index": 0,
    "return_to_start": false
  }' | jq '.'
echo -e "\n"

# Test 4: Error Cases
echo "4️⃣  Testing Error Cases..."

echo "   📍 Empty locations array:"
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{"locations": [], "return_to_start": true}' | jq '.'
echo -e "\n"

echo "   📍 Invalid latitude:"
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "id": "invalid_location",
        "name": "Invalid Location",
        "latitude": 999,
        "longitude": -74.0089
      }
    ],
    "return_to_start": true
  }' | jq '.'
echo -e "\n"

echo "   📍 Missing location ID:"
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "name": "Missing ID Location",
        "latitude": 40.7195,
        "longitude": -74.0089
      }
    ],
    "return_to_start": true
  }' | jq '.'
echo -e "\n"

# Test 5: Mixed Categories with Visit Time Override
echo "5️⃣  Testing Mixed Categories with Custom Visit Time..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "id": "morning_coffee",
        "name": "Morning Coffee",
        "latitude": 40.7420,
        "longitude": -74.0048,
        "category": "coffee_shop"
      },
      {
        "id": "business_meeting",
        "name": "Business Meeting at Bank",
        "latitude": 40.7414,
        "longitude": -73.9896,
        "category": "bank",
        "visit_duration_minutes": 45
      },
      {
        "id": "lunch_restaurant",
        "name": "Lunch Restaurant",
        "latitude": 40.7323,
        "longitude": -74.0027,
        "category": "restaurant"
      },
      {
        "id": "moma_museum",
        "name": "Museum of Modern Art",
        "latitude": 40.7614,
        "longitude": -73.9776,
        "category": "museum"
      }
    ],
    "start_index": 0,
    "return_to_start": false
  }' | jq '.'
echo -e "\n"

# Test 6: Single Location
echo "6️⃣  Testing Single Location..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "locations": [
      {
        "id": "single_location",
        "name": "Single Coffee Shop",
        "latitude": 40.7195,
        "longitude": -74.0089,
        "category": "coffee_shop"
      }
    ],
    "return_to_start": false
  }' | jq '.'
echo -e "\n"

echo "✅ All tests completed!"
echo "💡 Tip: Install jq for better JSON formatting: brew install jq"
echo "📊 New Features:"
echo "   - Category-based visit time estimation"
echo "   - Custom visit duration overrides"
echo "   - Detailed timing breakdown per location"
echo "   - Total travel vs visit time separation"
