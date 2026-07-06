import 'dart:convert';
import '../models/trip_segment.dart';
import 'api_client.dart';

typedef TransportLink = ({String provider, String mode, String url});

class TransportApiService {
  final ApiClient apiClient;

  TransportApiService(this.apiClient);

  Future<List<TransportLink>> links({
    required String mode, // 'flight' | 'ground'
    required String origin,
    required String destination,
    String? departDate,
    String? returnDate,
    int? passengers,
  }) async {
    final qp = <String, String>{
      'mode': mode,
      'origin': origin,
      'destination': destination,
      if (departDate != null) 'depart_date': departDate,
      if (returnDate != null) 'return_date': returnDate,
      if (passengers != null) 'passengers': '$passengers',
    };
    final uri = Uri.parse('${apiClient.baseUrl}/transport-links').replace(queryParameters: qp);
    final res = await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => (
                provider: e['provider'] as String,
                mode: e['mode'] as String,
                url: e['url'] as String,
              ))
          .toList();
    }
    throw Exception('Failed to get transport links (${res.statusCode})');
  }

  Future<TripSegment> addSegment(String tripId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/segments'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return TripSegment.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to add segment (${res.statusCode})');
  }

  Future<void> deleteSegment(String tripId, String segmentId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/segments/$segmentId'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to delete segment (${res.statusCode})');
    }
  }
}
