import 'dart:convert';
import '../models/traveler_preferences.dart';
import 'api_client.dart';

/// Wraps the authenticated /preferences endpoints (bearer token from ApiClient).
class PreferencesApiService {
  final ApiClient apiClient;

  PreferencesApiService(this.apiClient);

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    final token = apiClient.authToken;
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Future<TravelerPreferences> getPreferences() async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/preferences'), headers: _headers());
    if (res.statusCode == 200) {
      return TravelerPreferences.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to load preferences (${res.statusCode})');
  }

  Future<TravelerPreferences> savePreferences({
    String? budget,
    String? pace,
    required List<String> interests,
    String? homeAirport,
  }) async {
    final res = await apiClient.httpClient.put(
      Uri.parse('${apiClient.baseUrl}/preferences'),
      headers: _headers(json: true),
      body: jsonEncode({
        'budget': budget,
        'pace': pace,
        'interests': interests,
        'home_airport': homeAirport,
      }),
    );
    if (res.statusCode == 200) {
      return TravelerPreferences.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to save preferences (${res.statusCode})');
  }
}
