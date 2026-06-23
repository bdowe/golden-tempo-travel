# Travel Route Planner - Flutter App

A beautiful Flutter mobile app that consumes the Travel Route Planner Go API to provide intelligent route optimization for both locations and countries.

## Features

### 🗺️ **Route Optimizer**
- **Smart Location Routing**: Add multiple locations with coordinates, addresses, and categories
- **Operating Hours Integration**: Set operating hours for each location with automatic scheduling
- **Travel Time Optimization**: Minimize travel distances using Nearest Neighbor + 2-Opt algorithms
- **Visit Duration Planning**: Customize visit times or use intelligent category-based defaults
- **Time-Aware Planning**: Schedule routes with start times and dates
- **Beautiful Results**: Visual timeline showing optimized route with arrival/departure times

## Screenshots

> Note: This is a functional demo app. In a production version, you would add screenshots here showing the beautiful UI.

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Go API server running (see `../api/README.md`)
- iOS Simulator / Android Emulator or physical device

### Installation

1. **Navigate to the Flutter app directory**:
   ```bash
   cd src/packages/flutter-app
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Start the Go API server** (in another terminal):
   ```bash
   cd ../api
   go run .
   ```

4. **Run the app**:
   ```bash
   flutter run
   ```

### API Configuration

With Docker (`make docker-dev` or `make docker-deploy`), the app uses `/api/v1` via the gateway at `http://localhost:3000`. For local `flutter run` without Docker, the default is `http://localhost:8080/api/v1`. To change this:

1. Edit `lib/services/api_client.dart`
2. Update the `_baseUrl` constant to your API server address

## Architecture

### State Management
- **Riverpod**: Modern, type-safe state management with excellent developer experience
- **Provider Pattern**: Clean separation of business logic and UI components

### Project Structure
```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models (matching Go API structs)
│   ├── location.dart           # Location and operating hours models
│   └── route_request.dart      # Route optimization request/response
├── services/
│   └── api_client.dart         # HTTP client for API communication
├── providers/                  # Riverpod state providers
│   └── route_provider.dart     # Route optimization state
├── screens/                    # Main app screens
│   ├── home_screen.dart        # Navigation hub
│   └── route_optimizer_screen.dart
└── widgets/                    # Reusable UI components
    ├── location_input_dialog.dart
    ├── optimization_params_widget.dart
    └── route_results_widget.dart
```

### Key Features
- **Type-Safe Models**: Auto-generated JSON serialization matching Go API structs
- **Error Handling**: Comprehensive error handling with user-friendly messages
- **Loading States**: Beautiful loading indicators and smooth UX
- **Form Validation**: Input validation with helpful error messages
- **Material Design 3**: Modern, accessible UI following Material Design guidelines

## API Integration

The app integrates with the following Go API endpoints:

### Route Optimization
```
POST /api/v1/optimize-route
```
**Request**: List of locations with coordinates, categories, operating hours
**Response**: Optimized route with timing details and distance metrics

### Health Check
```
GET /api/v1/health
```
**Response**: API health status

## Development

### Code Generation
When you modify models, regenerate JSON serialization:
```bash
dart run build_runner build
```

### Testing
Run tests:
```bash
flutter test
```

### Analysis
Check code quality:
```bash
flutter analyze
```

## Example Usage

### Route Optimization Example
1. Add locations (restaurants, museums, shops, etc.)
2. Set categories for intelligent visit time estimation
3. Configure operating hours if needed
4. Set start time and date
5. Choose whether to return to starting point
6. Tap "Optimize Route" to get optimized itinerary

### Country Planning Example  
1. Add countries with capitals and coordinates
2. Set ideal travel seasons and months to avoid
3. Configure minimum stay durations
4. Set trip start date and total duration
5. Choose optimization strategy (distance/season/balanced)
6. Tap "Optimize Trip" to get optimized itinerary

## Built With

- **Flutter**: Google's UI toolkit for beautiful, natively compiled mobile apps
- **Riverpod**: Modern state management for Flutter
- **Material Design 3**: Latest design system for intuitive user interfaces
- **HTTP Package**: For seamless API communication
- **JSON Serialization**: Type-safe model generation and API integration

## Contributing

This is a demo application showcasing Flutter + Go API integration. In a production environment, you would:

1. Add comprehensive unit and integration tests
2. Implement proper error logging and analytics
3. Add offline support and caching
4. Implement user authentication
5. Add more detailed location and country data sources
6. Implement maps integration for visual route display
7. Add push notifications for trip reminders
8. Implement data persistence with local database

## License

This project is for demonstration purposes.