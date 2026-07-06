import 'dart:convert';
import '../models/admin_metrics.dart';
import 'api_client.dart';

/// GET /admin/metrics — requires an admin bearer token (enforced
/// server-side by adminMiddleware).
class AdminMetricsApiService {
  final ApiClient apiClient;

  AdminMetricsApiService(this.apiClient);

  Future<AdminMetrics> fetch({int days = 30}) async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}/admin/metrics?days=$days'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      return AdminMetrics.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to load metrics (${res.statusCode})');
  }
}
