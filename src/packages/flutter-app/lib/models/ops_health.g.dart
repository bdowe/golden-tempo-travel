// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ops_health.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HealthDb _$HealthDbFromJson(Map<String, dynamic> json) => HealthDb(
      status: json['status'] as String? ?? 'not_configured',
      pingMs: (json['ping_ms'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$HealthDbToJson(HealthDb instance) => <String, dynamic>{
      'status': instance.status,
      'ping_ms': instance.pingMs,
    };

ProviderStat _$ProviderStatFromJson(Map<String, dynamic> json) => ProviderStat(
      name: json['name'] as String? ?? '',
      configured: json['configured'] as bool? ?? false,
      note: json['note'] as String? ?? '',
    );

Map<String, dynamic> _$ProviderStatToJson(ProviderStat instance) =>
    <String, dynamic>{
      'name': instance.name,
      'configured': instance.configured,
      'note': instance.note,
    };

BuildInfo _$BuildInfoFromJson(Map<String, dynamic> json) => BuildInfo(
      release: json['release'] as String? ?? '',
      goVersion: json['go_version'] as String? ?? '',
      startedAt: json['started_at'] == null
          ? null
          : DateTime.parse(json['started_at'] as String),
      uptimeS: (json['uptime_s'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$BuildInfoToJson(BuildInfo instance) => <String, dynamic>{
      'release': instance.release,
      'go_version': instance.goVersion,
      'started_at': instance.startedAt?.toIso8601String(),
      'uptime_s': instance.uptimeS,
    };

BackupInfo _$BackupInfoFromJson(Map<String, dynamic> json) => BackupInfo(
      lastSuccessAt: json['last_success_at'] as String?,
      ageS: (json['age_s'] as num?)?.toInt(),
      stale: json['stale'] as bool? ?? false,
    );

Map<String, dynamic> _$BackupInfoToJson(BackupInfo instance) =>
    <String, dynamic>{
      'last_success_at': instance.lastSuccessAt,
      'age_s': instance.ageS,
      'stale': instance.stale,
    };

OpsHealth _$OpsHealthFromJson(Map<String, dynamic> json) => OpsHealth(
      db: json['db'] == null
          ? const HealthDb()
          : HealthDb.fromJson(json['db'] as Map<String, dynamic>),
      providers: (json['providers'] as List<dynamic>?)
              ?.map((e) => ProviderStat.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      build: json['build'] == null
          ? const BuildInfo()
          : BuildInfo.fromJson(json['build'] as Map<String, dynamic>),
      backups: json['backups'] == null
          ? const BackupInfo()
          : BackupInfo.fromJson(json['backups'] as Map<String, dynamic>),
      degraded: json['degraded'] as bool? ?? false,
      reasons: (json['reasons'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$OpsHealthToJson(OpsHealth instance) => <String, dynamic>{
      'db': instance.db,
      'providers': instance.providers,
      'build': instance.build,
      'backups': instance.backups,
      'degraded': instance.degraded,
      'reasons': instance.reasons,
    };
