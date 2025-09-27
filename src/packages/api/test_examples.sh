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

# Test 2: Simple NYC Tourist Route (5 locations) with start time
echo "2️⃣  Testing NYC Tourist Route (5 locations) with operating hours..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "start_time": "09:00",
    "start_date": "2024-03-15",
    "locations": [
      {
        "id": "starbucks_times_square",
        "name": "Starbucks Times Square",
        "latitude": 40.7589,
        "longitude": -73.9851,
        "address": "1585 Broadway, New York, NY 10036",
        "category": "coffee_shop",
        "hours": {
          "monday": "06:00-22:00",
          "tuesday": "06:00-22:00",
          "wednesday": "06:00-22:00",
          "thursday": "06:00-22:00",
          "friday": "06:00-22:00",
          "saturday": "06:30-22:00",
          "sunday": "06:30-21:00"
        }
      },
      {
        "id": "empire_state_building",
        "name": "Empire State Building",
        "latitude": 40.7484,
        "longitude": -73.9857,
        "address": "350 5th Ave, New York, NY 10118",
        "category": "tourist_attraction",
        "hours": {
          "monday": "10:00-22:00",
          "tuesday": "10:00-22:00",
          "wednesday": "10:00-22:00",
          "thursday": "10:00-22:00",
          "friday": "10:00-22:00",
          "saturday": "09:00-23:00",
          "sunday": "09:00-22:00"
        }
      },
      {
        "id": "statue_of_liberty",
        "name": "Statue of Liberty",
        "latitude": 40.6892,
        "longitude": -74.0445,
        "address": "Liberty Island, New York, NY 10004",
        "category": "tourist_attraction",
        "hours": {
          "monday": "09:30-17:00",
          "tuesday": "09:30-17:00",
          "wednesday": "09:30-17:00",
          "thursday": "09:30-17:00",
          "friday": "09:30-17:00",
          "saturday": "09:30-17:00",
          "sunday": "09:30-17:00"
        }
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

# Test 5: Time-aware route with operating hours (early morning start)
echo "5️⃣  Testing Early Morning Route (demonstrating closed locations)..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "start_time": "05:00",
    "start_date": "2024-03-18",
    "locations": [
      {
        "id": "early_coffee",
        "name": "Early Bird Coffee",
        "latitude": 40.7420,
        "longitude": -74.0048,
        "category": "coffee_shop",
        "hours": {
          "monday": "06:30-19:00",
          "tuesday": "06:30-19:00",
          "wednesday": "06:30-19:00",
          "thursday": "06:30-19:00",
          "friday": "06:30-19:00",
          "saturday": "07:00-19:00",
          "sunday": "07:00-18:00"
        }
      },
      {
        "id": "bank_meeting",
        "name": "Business Meeting at Bank",
        "latitude": 40.7414,
        "longitude": -73.9896,
        "category": "bank",
        "visit_duration_minutes": 45,
        "hours": {
          "monday": "09:00-17:00",
          "tuesday": "09:00-17:00",
          "wednesday": "09:00-17:00",
          "thursday": "09:00-17:00",
          "friday": "09:00-17:00",
          "saturday": "09:00-13:00",
          "sunday": "closed"
        }
      },
      {
        "id": "museum_visit",
        "name": "Metropolitan Museum",
        "latitude": 40.7794,
        "longitude": -73.9632,
        "category": "museum",
        "hours": {
          "monday": "10:00-17:00",
          "tuesday": "10:00-17:00",
          "wednesday": "10:00-17:00",
          "thursday": "10:00-17:00",
          "friday": "10:00-21:00",
          "saturday": "10:00-21:00",
          "sunday": "10:00-17:00"
        }
      }
    ],
    "start_index": 0,
    "return_to_start": false
  }' | jq '.'
echo -e "\n"

# Test 6: Mixed Categories with Visit Time Override
echo "6️⃣  Testing Mixed Categories with Custom Visit Time..."
curl -s -X POST "$API_BASE/optimize-route" \
  -H "Content-Type: application/json" \
  -d '{
    "start_time": "14:00",
    "locations": [
      {
        "id": "afternoon_coffee",
        "name": "Afternoon Coffee",
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
        "id": "dinner_restaurant",
        "name": "Dinner Restaurant",
        "latitude": 40.7323,
        "longitude": -74.0027,
        "category": "restaurant"
      }
    ],
    "start_index": 0,
    "return_to_start": false
  }' | jq '.'
echo -e "\n"

# Test 7: Single Location
echo "7️⃣  Testing Single Location..."
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

# Test 8: Country Route Optimization (Europe - Season Focus)
echo "8️⃣  Testing European Summer Route (Season Optimized)..."
curl -s -X POST "$API_BASE/optimize-countries" \
  -H "Content-Type: application/json" \
  -d '{
    "countries": [
      {
        "code": "IT",
        "name": "Italy",
        "capital": "Rome",
        "latitude": 41.8719,
        "longitude": 12.5674,
        "min_stay_days": 7,
        "continent": "Europe",
        "currency": "EUR",
        "ideal_seasons": [
          {
            "name": "spring",
            "start_month": 4,
            "end_month": 6,
            "description": "Mild weather, fewer crowds, perfect for sightseeing"
          }
        ],
        "avoid_months": [7, 8]
      },
      {
        "code": "FR",
        "name": "France",
        "capital": "Paris",
        "latitude": 46.2276,
        "longitude": 2.2137,
        "min_stay_days": 6,
        "continent": "Europe",
        "currency": "EUR",
        "ideal_seasons": [
          {
            "name": "spring",
            "start_month": 5,
            "end_month": 6,
            "description": "Beautiful weather, blooming gardens"
          }
        ]
      },
      {
        "code": "ES",
        "name": "Spain",
        "capital": "Madrid",
        "latitude": 40.4637,
        "longitude": -3.7492,
        "min_stay_days": 5,
        "continent": "Europe",
        "currency": "EUR",
        "ideal_seasons": [
          {
            "name": "spring",
            "start_month": 4,
            "end_month": 6,
            "description": "Perfect temperatures"
          }
        ]
      }
    ],
    "trip_start_date": "2024-05-01",
    "trip_duration_days": 21,
    "optimize_for": "season",
    "return_to_start": true
  }' | jq '.'
echo -e "\n"

# Test 9: Country Route Optimization (Distance Focus)
echo "9️⃣  Testing Central Europe Route (Distance Optimized)..."
curl -s -X POST "$API_BASE/optimize-countries" \
  -H "Content-Type: application/json" \
  -d '{
    "countries": [
      {
        "code": "DE",
        "name": "Germany",
        "capital": "Berlin",
        "latitude": 51.1657,
        "longitude": 10.4515,
        "min_stay_days": 5,
        "continent": "Europe"
      },
      {
        "code": "AT",
        "name": "Austria",
        "capital": "Vienna",
        "latitude": 47.5162,
        "longitude": 14.5501,
        "min_stay_days": 4,
        "continent": "Europe"
      },
      {
        "code": "CZ",
        "name": "Czech Republic",
        "capital": "Prague",
        "latitude": 49.8175,
        "longitude": 15.4730,
        "min_stay_days": 3,
        "continent": "Europe"
      }
    ],
    "start_country": "DE",
    "optimize_for": "distance",
    "return_to_start": false
  }' | jq '.'
echo -e "\n"

# Test 10: Country Route Optimization Error Cases
echo "🔟 Testing Country Optimization Error Cases..."

echo "   📍 Empty countries array:"
curl -s -X POST "$API_BASE/optimize-countries" \
  -H "Content-Type: application/json" \
  -d '{"countries": [], "optimize_for": "balanced"}' | jq '.'
echo -e "\n"

echo "   📍 Invalid optimization type:"
curl -s -X POST "$API_BASE/optimize-countries" \
  -H "Content-Type: application/json" \
  -d '{
    "countries": [
      {
        "code": "US",
        "name": "United States",
        "latitude": 39.8283,
        "longitude": -98.5795,
        "min_stay_days": 7
      }
    ],
    "optimize_for": "invalid_option"
  }' | jq '.'
echo -e "\n"

echo "✅ All tests completed!"
echo "💡 Tip: Install jq for better JSON formatting: brew install jq"
echo "📊 Features:"
echo "   🗺️  Location route optimization with operating hours"
echo "   🌍 Country route optimization with seasonal planning"
echo "   📅 Time-aware scheduling and business hours validation"
echo "   🎯 Multiple optimization strategies (distance/season/balanced)"
echo "   📍 Category-based visit time estimation"
echo "   ⏰ Real arrival/departure time calculation"
