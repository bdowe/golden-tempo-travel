import 'dart:convert';
import '../models/event.dart';
import '../models/source_link.dart';
import 'api_client.dart';

/// Wraps the /events/search endpoint (Ticketmaster-backed local events). The
/// endpoint is public, but we still send the bearer token when present, matching
/// the other services.
class EventsApiService {
  final ApiClient apiClient;

  EventsApiService(this.apiClient);

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
    final res = await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
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

  /// Curated Greek event-discovery links for a city + date window. Returns []
  /// for non-Greek cities (the API decides). Used as the trip-detail fallback
  /// when the structured events lookup is empty for a Greek city.
  Future<List<SourceLink>> greeceEventLinks(
    String city,
    String startDate,
    String endDate,
  ) async {
    final uri = Uri.parse('${apiClient.baseUrl}/events/greece-links').replace(
      queryParameters: {
        'city': city,
        'start_date': startDate,
        'end_date': endDate,
      },
    );
    final res = await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['links'] as List<dynamic>? ?? []);
      return list
          .map((e) => SourceLink.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to fetch Greek event links: ${res.body}',
      endpoint: 'events/greece-links',
    );
  }
}
