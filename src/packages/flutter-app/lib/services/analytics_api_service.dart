import 'dart:convert';
import 'api_client.dart';

/// First-party analytics: records the client-observed funnel moments (opening
/// a booking link, adding a browsed place to a trip). Strictly fire-and-forget
/// — failures are swallowed, tracking must never slow down or break the
/// experience.
class AnalyticsApiService {
  final ApiClient apiClient;

  AnalyticsApiService(this.apiClient);

  /// Records a place added to a trip from a browse surface
  /// (specs/add-to-itinerary). [source] is one of the server's closed set:
  /// 'local_rec', 'event', or 'guide_pin'.
  Future<void> recordItineraryItemAdded({
    required String tripId,
    required String source,
  }) async {
    final token = apiClient.authToken;
    if (token == null) return; // anonymous sessions are untracked
    try {
      await apiClient.httpClient.post(
        Uri.parse('${apiClient.baseUrl}/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event_type': 'itinerary_item_added',
          'trip_id': tripId,
          'metadata': {'source': source},
        }),
      );
    } catch (_) {
      // Silently dropped by design.
    }
  }

  Future<void> recordBookingLinkClicked({
    String? tripId,
    String? todoKey,
    String? provider,
    String? surface,
    String? kind,
  }) async {
    final token = apiClient.authToken;
    if (token == null) return; // anonymous sessions are untracked
    try {
      await apiClient.httpClient.post(
        Uri.parse('${apiClient.baseUrl}/events'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event_type': 'booking_link_clicked',
          if (tripId != null) 'trip_id': tripId,
          'metadata': {
            if (todoKey != null) 'todo_key': todoKey,
            if (provider != null) 'provider': provider,
            if (surface != null) 'surface': surface,
            if (kind != null) 'kind': kind,
          },
        }),
      );
    } catch (_) {
      // Silently dropped by design.
    }
  }
}
