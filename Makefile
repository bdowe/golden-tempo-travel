# Travel Route Planner - Development Makefile
.PHONY: help build run test clean docker-build docker-run api-build api-run api-test

# Variables
API_DIR = src/packages/api
DOCKER_IMAGE = travel-route-planner-api
DOCKER_TAG = latest

# Default target
help: ## Show this help message
	@echo "Travel Route Planner - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Docker commands
docker-build: ## Build the API Docker image
	docker-compose build travel-route-planner-api

docker-run: ## Run the API using Docker Compose
	docker-compose up

docker-run-bg: ## Run the API in background using Docker Compose
	docker-compose up -d

docker-stop: ## Stop Docker Compose services
	docker-compose down

docker-logs: ## Show Docker Compose logs
	docker-compose logs -f travel-route-planner-api

# API commands
api-deps: ## Download API dependencies
	cd $(API_DIR) && go mod tidy

api-build: ## Build the API binary
	cd $(API_DIR) && go build -o travel-route-planner .

api-run: ## Run the API locally
	cd $(API_DIR) && go run main.go route_optimizer.go country_optimizer.go

api-test: ## Run API tests
	cd $(API_DIR) && ./test_examples.sh

api-fmt: ## Format Go code
	cd $(API_DIR) && go fmt ./...

api-vet: ## Run go vet
	cd $(API_DIR) && go vet ./...

# Development commands
dev: docker-run ## Start development environment (alias for docker-run)

dev-api: api-run ## Start API development server

test: api-test ## Run all tests

clean: ## Clean up build artifacts
	cd $(API_DIR) && rm -f travel-route-planner
	docker-compose down
	docker system prune -f

# Setup commands
setup: ## Initial project setup
	@echo "Setting up Travel Route Planner development environment..."
	cd $(API_DIR) && go mod tidy
	@echo "Setup complete! Run 'make dev' to start development."

# Health check
health: ## Check API health
	curl -s http://localhost:8081/api/v1/health | jq '.' || echo "API not running or jq not installed"

# Quick test commands
test-route: ## Test route optimization endpoint
	curl -s -X POST http://localhost:8081/api/v1/optimize-route \
		-H "Content-Type: application/json" \
		-d @$(API_DIR)/test_data.json | jq '.'

test-countries: ## Test country optimization endpoint  
	curl -s -X POST http://localhost:8081/api/v1/optimize-countries \
		-H "Content-Type: application/json" \
		-d '{"countries":[{"code":"US","name":"United States","latitude":39.8283,"longitude":-98.5795,"min_stay_days":7}],"optimize_for":"balanced"}' | jq '.'

# Documentation
docs: ## Open API documentation in browser
	@echo "API Documentation:"
	@echo "  Health Check: http://localhost:8081/api/v1/health"
	@echo "  Route Optimization: POST http://localhost:8081/api/v1/optimize-route"
	@echo "  Country Optimization: POST http://localhost:8081/api/v1/optimize-countries"
	@echo ""
	@echo "See README.md for detailed API documentation"
