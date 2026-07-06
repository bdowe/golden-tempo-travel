import 'dart:convert';
import 'api_client.dart';

/// First-party analytics: records the one client-observed funnel moment
/// (opening a booking link). Strictly fire-and-forget — failures are
/// swallowed, tracking must never slow down or break the experience.
class AnalyticsApiService {
  final ApiClient apiClient;

  AnalyticsApiService(this.apiClient);

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
