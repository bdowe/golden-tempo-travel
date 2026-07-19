import 'dart:convert';
import '../models/checklist_item.dart';
import 'api_client.dart';

/// Wraps the per-trip packing & prep checklist endpoints
/// (`/trips/{id}/checklist`). Mirrors [BookingTodosApiService] conventions.
class ChecklistApiService {
  final ApiClient apiClient;

  ChecklistApiService(this.apiClient);

  List<ChecklistItem> _parseList(String body) {
    final list = jsonDecode(body) as List<dynamic>;
    return list
        .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChecklistItem>> list(String tripId) async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/checklist'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) return _parseList(res.body);
    throw Exception('Failed to load checklist (${res.statusCode})');
  }

  Future<ChecklistItem> add(
      String tripId, String title, String category) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/checklist'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode({'title': title, 'category': category}),
    );
    if (res.statusCode == 201) {
      return ChecklistItem.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to add checklist item (${res.statusCode})');
  }

  /// Partial update — pass only the fields to change (checked / title /
  /// category / position).
  Future<ChecklistItem> update(
      String tripId, String itemId, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/checklist/$itemId'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return ChecklistItem.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to update checklist item (${res.statusCode})');
  }

  Future<void> delete(String tripId, String itemId) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/trips/$tripId/checklist/$itemId'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception('Failed to delete checklist item (${res.statusCode})');
    }
  }
}
