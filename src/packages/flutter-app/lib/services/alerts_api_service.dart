import 'dart:convert';
import '../models/alert_event.dart';
import '../models/price_alert.dart';
import 'api_client.dart';

class AlertsApiService {
  final ApiClient apiClient;

  AlertsApiService(this.apiClient);

  String _errorMessage(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return 'Request failed ($status)';
  }

  Future<List<PriceAlert>> list() async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/alerts'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => PriceAlert.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(res.body, res.statusCode));
  }

  Future<PriceAlert> create(Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/alerts'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 201) {
      return PriceAlert.fromJson(jsonDecode(res.body));
    }
    throw Exception(_errorMessage(res.body, res.statusCode));
  }

  Future<PriceAlert> patch(String id, Map<String, dynamic> body) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/alerts/$id'),
      headers: apiClient.jsonHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode == 200) {
      return PriceAlert.fromJson(jsonDecode(res.body));
    }
    throw Exception(_errorMessage(res.body, res.statusCode));
  }

  Future<void> delete(String id) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/alerts/$id'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res.body, res.statusCode));
    }
  }

  /// The notification feed, newest-first (specs/price-alerts-v2).
  Future<List<AlertEvent>> listAlertEvents({int limit = 50}) async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/alerts/events?limit=$limit'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => AlertEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(_errorMessage(res.body, res.statusCode));
  }

  /// Marks all of the caller's events read (the mark-all read model — opening
  /// the center is the read action). Idempotent; returns 204.
  Future<void> markAlertEventsRead() async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/alerts/events/read'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res.body, res.statusCode));
    }
  }

  /// The unread badge number.
  Future<int> alertUnreadCount() async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/alerts/events/unread-count'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return (decoded['count'] as num?)?.toInt() ?? 0;
    }
    throw Exception(_errorMessage(res.body, res.statusCode));
  }
}
