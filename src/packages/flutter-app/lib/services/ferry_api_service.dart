import 'dart:convert';
import '../models/ferry_option.dart';
import 'api_client.dart';

/// Wraps the /ferries/search endpoint (Ferryhopper-backed ferry booking links).
/// Public, but sends the bearer token when present, matching the other services.
class FerryApiService {
  final ApiClient apiClient;

  FerryApiService(this.apiClient);

  /// Looks up ferry options for a route between two ports/islands.
  Future<List<FerryOption>> searchFerries(
    String origin,
    String destination, {
    String? date,
    int? passengers,
  }) async {
    final uri = Uri.parse('${apiClient.baseUrl}/ferries/search').replace(
      queryParameters: {
        'origin': origin,
        'destination': destination,
        if (date != null && date.isNotEmpty) 'date': date,
        if (passengers != null && passengers > 0)
          'passengers': '$passengers',
      },
    );
    final res = await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['options'] as List<dynamic>? ?? []);
      return list
          .map((e) => FerryOption.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to search ferries: ${res.body}',
      endpoint: 'ferries/search',
    );
  }
}
