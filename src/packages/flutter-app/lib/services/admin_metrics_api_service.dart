import 'dart:convert';
import '../models/admin_insights.dart';
import '../models/admin_metrics.dart';
import 'api_client.dart';

/// GET /admin/metrics and its /timeseries, /totals, /activity, /users
/// siblings — all require an admin bearer token (enforced server-side by
/// adminMiddleware).
class AdminMetricsApiService {
  final ApiClient apiClient;

  AdminMetricsApiService(this.apiClient);

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

  Future<AdminMetrics> fetch({int days = 30}) => _get(
      '/admin/metrics?days=$days', (json) => AdminMetrics.fromJson(json));

  Future<AdminTimeseries> fetchTimeseries({int days = 30}) => _get(
      '/admin/metrics/timeseries?days=$days',
      (json) => AdminTimeseries.fromJson(json));

  Future<AdminTotals> fetchTotals() =>
      _get('/admin/metrics/totals', (json) => AdminTotals.fromJson(json));

  /// [before] is the keyset cursor from [AdminActivityFeed.nextBefore];
  /// null fetches the newest page.
  Future<AdminActivityFeed> fetchActivity({int limit = 50, String? before}) {
    final cursor =
        before == null ? '' : '&before=${Uri.encodeQueryComponent(before)}';
    return _get('/admin/metrics/activity?limit=$limit$cursor',
        (json) => AdminActivityFeed.fromJson(json));
  }

  Future<AdminUserList> fetchUsers({int limit = 50, int offset = 0}) => _get(
      '/admin/metrics/users?limit=$limit&offset=$offset',
      (json) => AdminUserList.fromJson(json));
}
