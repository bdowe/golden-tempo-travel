import 'dart:convert';
import '../models/accommodation.dart';
import 'api_client.dart';

typedef ProviderLink = ({String provider, String url});

class AccommodationsApiService {
  final ApiClient apiClient;

  AccommodationsApiService(this.apiClient);

  Future<List<ProviderLink>> links({
    required String destination,
    String? checkIn,
    String? checkOut,
    int? guests,
  }) async {
    final qp = <String, String>{
      'destination': destination,
      if (checkIn != null) 'check_in': checkIn,
      if (checkOut != null) 'check_out': checkOut,
      if (guests != null) 'guests': '$guests',
    };
    final uri = Uri.parse('${apiClient.baseUrl}/accommodation-links').replace(queryParameters: qp);
    final res = await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => (provider: e['provider'] as String, url: e['url'] as String))
          .toList();
    }
    throw Exception('Failed to get accommodation links (${res.statusCode})');
  }

  Future<Accommodation> add(String tripId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/accommodations'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return Accommodation.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to add accommodation (${res.statusCode})');
  }

  /// Partial update; an empty body confirms a suggested draft (auto=false).
  Future<Accommodation> update(
      String tripId, String accId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/accommodations/$accId'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return Accommodation.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to update accommodation (${res.statusCode})');
  }

  Future<void> delete(String tripId, String accId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/accommodations/$accId'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to delete accommodation (${res.statusCode})');
    }
  }
}
