import 'package:flutter_riverpod/flutter_riverpod.dart';
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
