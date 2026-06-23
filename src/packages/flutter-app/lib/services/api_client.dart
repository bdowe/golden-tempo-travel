import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/route_request.dart';
import '../models/route_response.dart';

class ApiClient {
  /// Default for local `flutter run` without Docker gateway.
  /// Docker stacks use `--dart-define=API_BASE_URL=/api/v1` (same-origin).
  static const String _defaultBaseUrl = 'http://localhost:8080/api/v1';
  static const Duration _timeout = Duration(seconds: 30);
  
  late final String _baseUrl;
  final http.Client _client;

  /// The current session token, attached as a bearer credential by services
  /// that need authentication (e.g. trips). Set by the auth provider.
  String? authToken;

  ApiClient({String? baseUrl, http.Client? client}) : _client = client ?? http.Client() {
    // Use provided baseUrl, or environment variable, or default
    _baseUrl = baseUrl ??
        const String.fromEnvironment('API_BASE_URL', defaultValue: _defaultBaseUrl);
  }

  // Public getters for external access
  String get baseUrl => _baseUrl;
  http.Client get httpClient => _client;

  /// Optimize a route for locations
  Future<RouteResponse> optimizeRoute(RouteRequest request) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/optimize-route'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> jsonData = jsonDecode(response.body);
          return RouteResponse.fromJson(jsonData);
        } catch (e) {
          throw ApiException(
            statusCode: 0,
            message: 'Failed to parse route response: $e',
            endpoint: 'optimize-route',
          );
        }
      } else {
        throw ApiException(
          statusCode: response.statusCode,
          message: 'Failed to optimize route: ${response.body}',
          endpoint: 'optimize-route',
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
        endpoint: 'optimize-route',
      );
    }
  }

  /// Check API health
  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/health'),
            headers: {
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw ApiException(
          statusCode: response.statusCode,
          message: 'Health check failed: ${response.body}',
          endpoint: 'health',
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
        endpoint: 'health',
      );
    }
  }

  /// Close the HTTP client
  void close() {
    _client.close();
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String endpoint;

  const ApiException({
    required this.statusCode,
    required this.message,
    required this.endpoint,
  });

  @override
  String toString() {
    return 'ApiException(statusCode: $statusCode, message: $message, endpoint: $endpoint)';
  }

  /// User-friendly error message
  String get userFriendlyMessage {
    switch (statusCode) {
      case 0:
        return 'Please check your internet connection and try again.';
      case 400:
        return 'Invalid request. Please check your input and try again.';
      case 404:
        return 'Service not found. Please try again later.';
      case 500:
        return 'Server error. Please try again later.';
      case 503:
        return 'Service temporarily unavailable. Please try again later.';
      default:
        return 'An unexpected error occurred. Please try again.';
    }
  }

  /// Whether this is a network-related error
  bool get isNetworkError => statusCode == 0;

  /// Whether this is a client error (4xx)
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// Whether this is a server error (5xx)
  bool get isServerError => statusCode >= 500;
}
