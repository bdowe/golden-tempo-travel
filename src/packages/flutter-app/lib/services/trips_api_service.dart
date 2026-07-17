import 'dart:convert';
import '../models/itinerary_item.dart';
import '../models/shared_trip.dart';
import '../models/trip.dart';
import 'api_client.dart';

/// Wraps the authenticated /trips endpoints. Reads the bearer token from the
/// shared ApiClient at call time so it always reflects the current session.
class TripsApiService {
  final ApiClient apiClient;

  TripsApiService(this.apiClient);

  Future<List<Trip>> listTrips() async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/trips'), headers: apiClient.jsonHeaders());
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
      headers: apiClient.jsonHeaders(json: true),
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
    final res = await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load trip versions (${res.statusCode})');
  }

  /// Cheap freshness poll for shared trips (specs/shared-trip-freshness).
  /// Returns the trip's updated_at plus who last edited (null for unknown).
  Future<({DateTime updatedAt, String? updatedBy, String? updatedByName})>
      getTripStatus(String id) async {
    final res = await apiClient.httpClient.get(
        Uri.parse('${apiClient.baseUrl}/trips/$id/status'),
        headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        updatedAt: DateTime.parse(body['updated_at'] as String),
        updatedBy: body['updated_by'] as String?,
        updatedByName: body['updated_by_name'] as String?,
      );
    }
    throw Exception('Failed to load trip status (${res.statusCode})');
  }

  Future<Trip> getTrip(String id) async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/trips/$id'), headers: apiClient.jsonHeaders());
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
      headers: apiClient.jsonHeaders(json: true),
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
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to add place (${res.statusCode})');
  }

  /// Mints (or returns the existing) share link token for a trip.
  /// Idempotent per (trip lineage, role); role is 'viewer' or 'editor'.
  Future<String> createShareLink(String tripId,
      {String role = 'viewer'}) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/share'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode({'role': role}),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String;
    }
    throw Exception('Failed to create share link (${res.statusCode})');
  }

  /// Redeems an editor-role share token; returns the trip id to open.
  Future<String> joinSharedTrip(String token) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/shared/$token/join'),
      headers: apiClient.jsonHeaders(json: true),
    );
    if (res.statusCode == 200) {
      return (jsonDecode(res.body) as Map<String, dynamic>)['trip_id']
          as String;
    }
    throw Exception('Failed to join trip (${res.statusCode})');
  }

  /// Trips shared with the signed-in user (latest version per lineage).
  Future<List<Trip>> listSharedWithMe() async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/trips/shared-with-me'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Trip.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw Exception('Failed to load shared trips (${res.statusCode})');
  }

  /// Owner-only: active co-planners on a trip.
  Future<List<({String userId, String displayName, String email})>>
      listCollaborators(String tripId) async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/collaborators'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => (
                userId: e['user_id'] as String,
                displayName: (e['display_name'] as String?) ?? '',
                email: (e['email'] as String?) ?? '',
              ))
          .toList();
    }
    throw Exception('Failed to load co-planners (${res.statusCode})');
  }

  /// Owner-only: removes a co-planner's access.
  Future<void> removeCollaborator(String tripId, String userId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/collaborators/$userId'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to remove co-planner (${res.statusCode})');
    }
  }

  Future<void> revokeShareLink(String tripId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/share'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to revoke share link (${res.statusCode})');
    }
  }

  /// Public read of a shared trip — works without a session.
  Future<SharedTrip> getSharedTrip(String token) async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/shared/$token'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      return SharedTrip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Shared trip not found (${res.statusCode})');
  }

  /// Copies a shared trip into the signed-in caller's trips (status draft).
  Future<Trip> duplicateSharedTrip(String token) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/shared/$token/duplicate'),
      headers: apiClient.jsonHeaders(json: true),
    );
    if (res.statusCode == 201) {
      return Trip.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to save a copy (${res.statusCode})');
  }

  /// Partial update of one itinerary item; absent fields keep their value.
  Future<ItineraryItem> updateItineraryItem(
      String tripId, String itemId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/items/$itemId'),
      headers: apiClient.jsonHeaders(json: true),
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
      headers: apiClient.jsonHeaders(),
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
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode({'item_ids': itemIds}),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to reorder itinerary (${res.statusCode})');
    }
  }

  Future<void> deleteTrip(String id) async {
    final res = await apiClient.httpClient
        .delete(Uri.parse('${apiClient.baseUrl}/trips/$id'), headers: apiClient.jsonHeaders());
    if (res.statusCode != 204) {
      throw Exception('Failed to delete trip (${res.statusCode})');
    }
  }
}
