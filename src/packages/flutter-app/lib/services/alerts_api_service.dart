import 'dart:convert';
import '../models/price_alert.dart';
import 'api_client.dart';

class AlertsApiService {
  final ApiClient apiClient;

  AlertsApiService(this.apiClient);

  Map<String, String> _headers({bool json = false}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (json) h['Content-Type'] = 'application/json';
    final token = apiClient.authToken;
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

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
      headers: _headers(),
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
      headers: _headers(json: true),
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
      headers: _headers(json: true),
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
      headers: _headers(),
    );
    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res.body, res.statusCode));
    }
  }
}
