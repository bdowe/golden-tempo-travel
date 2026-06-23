import 'dart:convert';
import '../models/event.dart';
import 'api_client.dart';

/// Wraps the /events/search endpoint (Ticketmaster-backed local events). The
/// endpoint is public, but we still send the bearer token when present, matching
/// the other services.
class EventsApiService {
  final ApiClient apiClient;

  EventsApiService(this.apiClient);

  Map<String, String> _headers() {
    final h = <String, String>{'Accept': 'application/json'};
    final token = apiClient.authToken;
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  /// Looks up events in [city] between [startDate] and [endDate] (YYYY-MM-DD).
  Future<List<Event>> searchEvents(
    String city,
    String startDate,
    String endDate, {
    String? category,
  }) async {
    final uri = Uri.parse('${apiClient.baseUrl}/events/search').replace(
      queryParameters: {
        'city': city,
        'start_date': startDate,
        'end_date': endDate,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['events'] as List<dynamic>? ?? []);
      return list
          .map((e) => Event.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to search events: ${res.body}',
      endpoint: 'events/search',
    );
  }
}
