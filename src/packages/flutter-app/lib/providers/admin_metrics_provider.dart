import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_insights.dart';
import '../models/admin_metrics.dart';
import '../services/admin_metrics_api_service.dart';
import 'api_client_provider.dart';

final adminMetricsApiServiceProvider =
    Provider<AdminMetricsApiService>((ref) {
  return AdminMetricsApiService(ref.watch(apiClientProvider));
});

/// Metrics for a trailing window in days. FutureProvider.family so switching
/// 7/30/90 re-fetches and caches per window.
final adminMetricsProvider =
    FutureProvider.family<AdminMetrics, int>((ref, days) async {
  return ref.watch(adminMetricsApiServiceProvider).fetch(days: days);
});

/// Daily trend buckets, keyed by the same days window as [adminMetricsProvider].
final adminTimeseriesProvider =
    FutureProvider.family<AdminTimeseries, int>((ref, days) async {
  return ref.watch(adminMetricsApiServiceProvider).fetchTimeseries(days: days);
});

/// All-time domain-table counts — no window key, there is exactly one answer.
final adminTotalsProvider = FutureProvider<AdminTotals>((ref) async {
  return ref.watch(adminMetricsApiServiceProvider).fetchTotals();
});

/// First page of the activity tail. Older pages are fetched imperatively by
/// the Activity pane (keyset cursor) and appended to local widget state —
/// invalidating this provider resets to the newest page.
final adminActivityProvider = FutureProvider<AdminActivityFeed>((ref) async {
  return ref.watch(adminMetricsApiServiceProvider).fetchActivity();
});

/// One offset page of the per-user aggregates, keyed by offset.
final adminUsersProvider =
    FutureProvider.family<AdminUserList, int>((ref, offset) async {
  return ref.watch(adminMetricsApiServiceProvider).fetchUsers(offset: offset);
});
