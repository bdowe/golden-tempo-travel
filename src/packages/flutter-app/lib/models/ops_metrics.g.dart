// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ops_metrics.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProcessStats _$ProcessStatsFromJson(Map<String, dynamic> json) => ProcessStats(
      uptimeS: (json['uptime_s'] as num?)?.toInt() ?? 0,
      goroutines: (json['goroutines'] as num?)?.toInt() ?? 0,
      memAllocBytes: (json['mem_alloc_bytes'] as num?)?.toInt() ?? 0,
      memSysBytes: (json['mem_sys_bytes'] as num?)?.toInt() ?? 0,
      gomaxprocs: (json['gomaxprocs'] as num?)?.toInt() ?? 0,
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
    );

Map<String, dynamic> _$ProcessStatsToJson(ProcessStats instance) =>
    <String, dynamic>{
      'uptime_s': instance.uptimeS,
      'goroutines': instance.goroutines,
      'mem_alloc_bytes': instance.memAllocBytes,
      'mem_sys_bytes': instance.memSysBytes,
      'gomaxprocs': instance.gomaxprocs,
      'started_at': instance.startedAt?.toIso8601String(),
    };

RouteMetric _$RouteMetricFromJson(Map<String, dynamic> json) => RouteMetric(
      route: json['route'] as String? ?? '',
      method: json['method'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      byClass: (json['by_class'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toInt()),
          ) ??
          const {},
      errorRate: (json['error_rate'] as num?)?.toDouble() ?? 0,
      p50Ms: (json['p50_ms'] as num?)?.toDouble() ?? 0,
      p95Ms: (json['p95_ms'] as num?)?.toDouble() ?? 0,
      p99Ms: (json['p99_ms'] as num?)?.toDouble() ?? 0,
      meanMs: (json['mean_ms'] as num?)?.toDouble() ?? 0,
      lastSeen: json['last_seen'] == null
          ? null
          : DateTime.parse(json['last_seen'] as String),
    );

Map<String, dynamic> _$RouteMetricToJson(RouteMetric instance) =>
    <String, dynamic>{
      'route': instance.route,
      'method': instance.method,
      'count': instance.count,
      'by_class': instance.byClass,
      'error_rate': instance.errorRate,
      'p50_ms': instance.p50Ms,
      'p95_ms': instance.p95Ms,
      'p99_ms': instance.p99Ms,
      'mean_ms': instance.meanMs,
      'last_seen': instance.lastSeen?.toIso8601String(),
    };

RequestMetrics _$RequestMetricsFromJson(Map<String, dynamic> json) =>
    RequestMetrics(
      total: (json['total'] as num?)?.toInt() ?? 0,
      byClass: (json['by_class'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, (e as num).toInt()),
          ) ??
          const {},
      routes: (json['routes'] as List<dynamic>?)
              ?.map((e) => RouteMetric.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$RequestMetricsToJson(RequestMetrics instance) =>
    <String, dynamic>{
      'total': instance.total,
      'by_class': instance.byClass,
      'routes': instance.routes,
    };

UpstreamStats _$UpstreamStatsFromJson(Map<String, dynamic> json) =>
    UpstreamStats(
      placesUpstreamCalls:
          (json['places_upstream_calls'] as num?)?.toInt() ?? 0,
      placesCacheHits: (json['places_cache_hits'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$UpstreamStatsToJson(UpstreamStats instance) =>
    <String, dynamic>{
      'places_upstream_calls': instance.placesUpstreamCalls,
      'places_cache_hits': instance.placesCacheHits,
    };

OpsMetrics _$OpsMetricsFromJson(Map<String, dynamic> json) => OpsMetrics(
      process: json['process'] == null
          ? const ProcessStats()
          : ProcessStats.fromJson(json['process'] as Map<String, dynamic>),
      requests: json['requests'] == null
          ? const RequestMetrics()
          : RequestMetrics.fromJson(json['requests'] as Map<String, dynamic>),
      upstream: json['upstream'] == null
          ? const UpstreamStats()
          : UpstreamStats.fromJson(json['upstream'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$OpsMetricsToJson(OpsMetrics instance) =>
    <String, dynamic>{
      'process': instance.process,
      'requests': instance.requests,
      'upstream': instance.upstream,
    };
