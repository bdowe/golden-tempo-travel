import 'dart:convert';
import '../models/ops_health.dart';
import '../models/ops_metrics.dart';
import 'api_client.dart';

/// GET /admin/ops/metrics and /admin/ops/health — live process/request metrics
/// and dependency/backup health for the System Health dashboard tab. Both
/// require an admin bearer token (enforced server-side by adminMiddleware).
class OpsAdminApiService {
  final ApiClient apiClient;

  OpsAdminApiService(this.apiClient);

  Future<T> _get<T>(String pathAndQuery, T Function(dynamic) parse) async {
    final res = await apiClient.httpClient.get(
      Uri.parse('${apiClient.baseUrl}$pathAndQuery'),
      headers: apiClient.jsonHeaders(),
    );
    if (res.statusCode == 200) {
      return parse(jsonDecode(res.body));
    }
    throw Exception('Failed to load $pathAndQuery (${res.statusCode})');
  }

  Future<OpsMetrics> getOpsMetrics() =>
      _get('/admin/ops/metrics', (json) => OpsMetrics.fromJson(json));

  Future<OpsHealth> getOpsHealth() =>
      _get('/admin/ops/health', (json) => OpsHealth.fromJson(json));
}
