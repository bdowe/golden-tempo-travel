import 'dart:convert';
import '../models/traveler_preferences.dart';
import 'api_client.dart';

/// Wraps the authenticated /preferences endpoints (bearer token from ApiClient).
class PreferencesApiService {
  final ApiClient apiClient;

  PreferencesApiService(this.apiClient);

  Future<TravelerPreferences> getPreferences() async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/preferences'), headers: apiClient.jsonHeaders());
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
    String? profileNotes,
  }) async {
    final res = await apiClient.httpClient.put(
      Uri.parse('${apiClient.baseUrl}/preferences'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode({
        'budget': budget,
        'pace': pace,
        'interests': interests,
        'home_airport': homeAirport,
        'profile_notes': profileNotes,
      }),
    );
    if (res.statusCode == 200) {
      return TravelerPreferences.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to save preferences (${res.statusCode})');
  }
}
