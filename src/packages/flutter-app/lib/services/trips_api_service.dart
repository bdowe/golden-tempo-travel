import 'dart:convert';
import '../models/itinerary_item.dart';
import '../models/trip.dart';
import 'api_client.dart';

/// Wraps the authenticated /trips endpoints. Reads the bearer token from the
/// shared ApiClient at call time so it always reflects the current session.
class TripsApiService {
  final ApiClient apiClient;

  TripsApiService(this.apiClient);

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    final token = apiClient.authToken;
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  Future<List<Trip>> listTrips() async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/trips'), headers: _headers());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load trips (${res.statusCode})');
  }

  /// Ensures the trip has a chat_id (assigning one to legacy trips) and returns
  /// it, so the AI agent can reopen the trip and append refinements as versions.
  Future<String> startRefineSession(String tripId) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/refine'),
      headers: _headers(json: true),
    );
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['chat_id'] as String;
    }
    throw Exception('Failed to start refine session (${res.statusCode})');
  }

  /// Admin-only: every itinerary version a chat produced (newest first).
  Future<List<Trip>> listTripVersions(String chatId) async {
    final uri = Uri.parse('${apiClient.baseUrl}/trips/versions')
        .replace(queryParameters: {'chat_id': chatId});
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load trip versions (${res.statusCode})');
  }

  Future<Trip> getTrip(String id) async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/trips/$id'), headers: _headers());
    if (res.statusCode == 200) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to load trip (${res.statusCode})');
  }

  Future<Trip> patchTrip(
    String id, {
    String? title,
    String? startDate,
    String? endDate,
    String? status,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (startDate != null) body['start_date'] = startDate;
    if (endDate != null) body['end_date'] = endDate;
    if (status != null) body['status'] = status;

    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/trips/$id'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to update trip (${res.statusCode})');
  }

  /// Manually adds one itinerary item; the server slots it at the end of its
  /// chosen day. Returns the full updated trip (items reloaded, in order).
  Future<Trip> addItineraryItem(String tripId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/items'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to add place (${res.statusCode})');
  }

  /// Partial update of one itinerary item; absent fields keep their value.
  Future<ItineraryItem> updateItineraryItem(
      String tripId, String itemId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/items/$itemId'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return ItineraryItem.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to update place (${res.statusCode})');
  }

  Future<void> deleteItineraryItem(String tripId, String itemId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/items/$itemId'),
      headers: _headers(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to delete place (${res.statusCode})');
    }
  }

  /// Submits the full-trip item ordering (every item id, new order). The
  /// server 409s if the list doesn't exactly match its current item set.
  Future<void> reorderItineraryItems(String tripId, List<String> itemIds) async {
    final res = await apiClient.httpClient.put(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/items/order'),
      headers: _headers(json: true),
      body: jsonEncode({'item_ids': itemIds}),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to reorder itinerary (${res.statusCode})');
    }
  }

  Future<void> deleteTrip(String id) async {
    final res = await apiClient.httpClient
        .delete(Uri.parse('${apiClient.baseUrl}/trips/$id'), headers: _headers());
    if (res.statusCode != 204) {
      throw Exception('Failed to delete trip (${res.statusCode})');
    }
  }
}
