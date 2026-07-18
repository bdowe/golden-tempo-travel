import 'dart:convert';
import '../models/accommodation.dart';
import '../models/trip_segment.dart';
import 'api_client.dart';

/// The server's fresh stay/segment lists after a booking-drafts sync.
typedef BookingDraftsResult = ({
  List<Accommodation> stays,
  List<TripSegment> segments,
});

class BookingDraftsApiService {
  final ApiClient apiClient;

  BookingDraftsApiService(this.apiClient);

  /// Upserts the itinerary-derived draft stays/transports and returns the
  /// full (drafts + confirmed) lists. The server never touches confirmed
  /// rows or dismissed drafts and prunes drafts whose legs no longer exist.
  Future<BookingDraftsResult> syncDrafts(
      String tripId, Map<String, dynamic> payload) async {
    final res = await apiClient.httpClient.put(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/booking-drafts'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(payload),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final stays = (body['accommodations'] as List<dynamic>? ?? const [])
          .map((e) => Accommodation.fromJson(e as Map<String, dynamic>))
          .toList();
      final segments = (body['segments'] as List<dynamic>? ?? const [])
          .map((e) => TripSegment.fromJson(e as Map<String, dynamic>))
          .toList();
      return (stays: stays, segments: segments);
    }
    throw Exception('Failed to sync booking drafts (${res.statusCode})');
  }
}
