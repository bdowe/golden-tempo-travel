import 'package:json_annotation/json_annotation.dart';

part 'ops_health.g.dart';

/// Dependency + build + backup health from GET /admin/ops/health — an
/// admin-only snapshot powering the System Health dashboard tab. snake_case
/// JSON keys via [FieldRename.snake].

/// Database reachability. [status] is one of "ok" | "unreachable" |
/// "not_configured".
@JsonSerializable(fieldRename: FieldRename.snake)
class HealthDb {
  final String status;
  final int pingMs;

  const HealthDb({this.status = 'not_configured', this.pingMs = 0});

  factory HealthDb.fromJson(Map<String, dynamic> json) =>
      _$HealthDbFromJson(json);
  Map<String, dynamic> toJson() => _$HealthDbToJson(this);
}

/// A single upstream provider and whether its credentials are configured.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProviderStat {
  final String name;
  final bool configured;
  final String note;

  const ProviderStat({
    this.name = '',
    this.configured = false,
    this.note = '',
  });

  factory ProviderStat.fromJson(Map<String, dynamic> json) =>
      _$ProviderStatFromJson(json);
  Map<String, dynamic> toJson() => _$ProviderStatToJson(this);
}

/// Build identity + process uptime.
@JsonSerializable(fieldRename: FieldRename.snake)
class BuildInfo {
  final String release;
  final String goVersion;
  final DateTime? startedAt;
  final int uptimeS;

  const BuildInfo({
    this.release = '',
    this.goVersion = '',
    this.startedAt,
    this.uptimeS = 0,
  });

  factory BuildInfo.fromJson(Map<String, dynamic> json) =>
      _$BuildInfoFromJson(json);
  Map<String, dynamic> toJson() => _$BuildInfoToJson(this);
}

/// Backup freshness. [lastSuccessAt]/[ageS] are null when no backup has been
/// recorded yet; [stale] flags an over-age backup.
@JsonSerializable(fieldRename: FieldRename.snake)
class BackupInfo {
  final String? lastSuccessAt;
  final int? ageS;
  final bool stale;

  const BackupInfo({this.lastSuccessAt, this.ageS, this.stale = false});

  factory BackupInfo.fromJson(Map<String, dynamic> json) =>
      _$BackupInfoFromJson(json);
  Map<String, dynamic> toJson() => _$BackupInfoToJson(this);
}

/// Mirror of GET /admin/ops/health.
@JsonSerializable(fieldRename: FieldRename.snake)
class OpsHealth {
  final HealthDb db;
  final List<ProviderStat> providers;
  final BuildInfo build;
  final BackupInfo backups;
  final bool degraded;
  final List<String> reasons;

  const OpsHealth({
    this.db = const HealthDb(),
    this.providers = const [],
    this.build = const BuildInfo(),
    this.backups = const BackupInfo(),
    this.degraded = false,
    this.reasons = const [],
  });

  factory OpsHealth.fromJson(Map<String, dynamic> json) =>
      _$OpsHealthFromJson(json);
  Map<String, dynamic> toJson() => _$OpsHealthToJson(this);
}
