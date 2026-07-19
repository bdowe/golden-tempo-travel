import 'dart:convert';
import '../models/trip_finding.dart';
import 'api_client.dart';

/// Wraps the per-trip health review endpoint (`GET /trips/{id}/review`).
/// Read-only; mirrors [ChecklistApiService] conventions. The optional
/// [checkHours] flag opts into the slower opening-hours check (real Google
/// lookups land in a later PR — a harmless no-op until then).
class TripReviewApiService {
  final ApiClient apiClient;

  TripReviewApiService(this.apiClient);

  Future<List<TripFinding>> getReview(String tripId,
      {bool checkHours = false}) async {
    final res = await apiClient.httpClient.get(
      Uri.parse(
          '${apiClient.baseUrl}/trips/$tripId/review?check_hours=$checkHours'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['findings'] as List<dynamic>?) ?? const [];
      return list
          .map((e) => TripFinding.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load trip review (${res.statusCode})');
  }
}
