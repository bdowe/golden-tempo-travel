import 'dart:convert';
import '../models/booking_todo.dart';
import 'api_client.dart';

class BookingTodosApiService {
  final ApiClient apiClient;

  BookingTodosApiService(this.apiClient);

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    final token = apiClient.authToken;
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  List<BookingTodo> _parseList(String body) {
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map((e) => BookingTodo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Upserts the itinerary-derived auto-TODOs and returns the full list. The
  /// server preserves booked state for surviving keys and prunes stale ones.
  Future<List<BookingTodo>> syncTodos(
      String tripId, List<Map<String, dynamic>> derived) async {
    final res = await apiClient.httpClient.put(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/booking-todos'),
      headers: _headers(json: true),
      body: jsonEncode(derived),
    );
    if (res.statusCode == 200) return _parseList(res.body);
    throw Exception('Failed to sync booking todos (${res.statusCode})');
  }

  Future<BookingTodo> addTodo(String tripId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/booking-todos'),
      headers: _headers(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return BookingTodo.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to add booking todo (${res.statusCode})');
  }

  Future<BookingTodo> setBooked(
      String tripId, String todoId, bool booked) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/booking-todos/$todoId'),
      headers: _headers(json: true),
      body: jsonEncode({'booked': booked}),
    );
    if (res.statusCode == 200) {
      return BookingTodo.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to update booking todo (${res.statusCode})');
  }

  Future<void> delete(String tripId, String todoId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/booking-todos/$todoId'),
      headers: _headers(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to delete booking todo (${res.statusCode})');
    }
  }
}
