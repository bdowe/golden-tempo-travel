import 'package:json_annotation/json_annotation.dart';

part 'ops_metrics.g.dart';

/// Live process + request metrics from GET /admin/ops/metrics — an admin-only,
/// instantaneous snapshot (not windowed like /admin/metrics). Powers the
/// System Health dashboard tab. snake_case JSON keys via [FieldRename.snake].

/// Runtime stats for the API process.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProcessStats {
  final int uptimeS;
  final int goroutines;
  final int memAllocBytes;
  final int memSysBytes;
  final int gomaxprocs;
  final DateTime? startedAt;

  const ProcessStats({
    this.uptimeS = 0,
    this.goroutines = 0,
    this.memAllocBytes = 0,
    this.memSysBytes = 0,
    this.gomaxprocs = 0,
    this.startedAt,
  });

  factory ProcessStats.fromJson(Map<String, dynamic> json) =>
      _$ProcessStatsFromJson(json);
  Map<String, dynamic> toJson() => _$ProcessStatsToJson(this);
}

/// Per-route request counters + latency percentiles.
@JsonSerializable(fieldRename: FieldRename.snake)
class RouteMetric {
  final String route;
  final String method;
  final int count;

  /// Response-class counts keyed "2xx" / "3xx" / "4xx" / "5xx".
  final Map<String, int> byClass;
  final double errorRate;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final double meanMs;
  final DateTime? lastSeen;

  const RouteMetric({
    this.route = '',
    this.method = '',
    this.count = 0,
    this.byClass = const {},
    this.errorRate = 0,
    this.p50Ms = 0,
    this.p95Ms = 0,
    this.p99Ms = 0,
    this.meanMs = 0,
    this.lastSeen,
  });

  factory RouteMetric.fromJson(Map<String, dynamic> json) =>
      _$RouteMetricFromJson(json);
  Map<String, dynamic> toJson() => _$RouteMetricToJson(this);
}

/// Aggregate request counters plus the per-route breakdown.
@JsonSerializable(fieldRename: FieldRename.snake)
class RequestMetrics {
  final int total;

  /// Response-class totals keyed "2xx" / "3xx" / "4xx" / "5xx".
  final Map<String, int> byClass;
  final List<RouteMetric> routes;

  const RequestMetrics({
    this.total = 0,
    this.byClass = const {},
    this.routes = const [],
  });

  /// 4xx + 5xx as a fraction of [total] (0 when no requests seen).
  double get errorRate {
    if (total == 0) return 0;
    final errors = (byClass['4xx'] ?? 0) + (byClass['5xx'] ?? 0);
    return errors / total;
  }

  factory RequestMetrics.fromJson(Map<String, dynamic> json) =>
      _$RequestMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$RequestMetricsToJson(this);
}

/// Upstream provider call/cache counters (process-lifetime).
@JsonSerializable(fieldRename: FieldRename.snake)
class UpstreamStats {
  final int placesUpstreamCalls;
  final int placesCacheHits;

  const UpstreamStats({
    this.placesUpstreamCalls = 0,
    this.placesCacheHits = 0,
  });

  factory UpstreamStats.fromJson(Map<String, dynamic> json) =>
      _$UpstreamStatsFromJson(json);
  Map<String, dynamic> toJson() => _$UpstreamStatsToJson(this);
}

/// Mirror of GET /admin/ops/metrics.
@JsonSerializable(fieldRename: FieldRename.snake)
class OpsMetrics {
  final ProcessStats process;
  final RequestMetrics requests;
  final UpstreamStats upstream;

  const OpsMetrics({
    this.process = const ProcessStats(),
    this.requests = const RequestMetrics(),
    this.upstream = const UpstreamStats(),
  });

  factory OpsMetrics.fromJson(Map<String, dynamic> json) =>
      _$OpsMetricsFromJson(json);
  Map<String, dynamic> toJson() => _$OpsMetricsToJson(this);
}
