import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ops_health.dart';
import '../models/ops_metrics.dart';
import '../providers/ops_admin_provider.dart';
import '../theme/spacing.dart';
import 'empty_state.dart';
import 'page_container.dart';
import 'section_header.dart';
import 'status_pill.dart';

/// The "Health" tab of the admin dashboard: a live snapshot of the API
/// process, request mix, dependency health, and backup freshness. Auto-refreshes
/// every 10s (paused while the app is backgrounded) and supports pull-to-refresh.
class HealthPane extends ConsumerStatefulWidget {
  const HealthPane({super.key});

  @override
  ConsumerState<HealthPane> createState() => _HealthPaneState();
}

class _HealthPaneState extends ConsumerState<HealthPane>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _refreshInterval = Duration(seconds: 10);
  Timer? _timer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(opsMetricsProvider);
    ref.invalidate(opsHealthProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause polling in the background; resume (and refresh once) on return.
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _refresh();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final metrics = ref.watch(opsMetricsProvider);
    final health = ref.watch(opsHealthProvider);

    return PageContainer(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(opsMetricsProvider);
          ref.invalidate(opsHealthProvider);
          await Future.wait([
            ref.read(opsMetricsProvider.future),
            ref.read(opsHealthProvider.future),
          ]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            metrics.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => EmptyState(
                icon: Icons.cloud_off,
                title: 'Could not load metrics',
                message: '$e',
                actions: [
                  FilledButton(
                    onPressed: () => ref.invalidate(opsMetricsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (m) => _MetricsSection(metrics: m),
            ),
            const SizedBox(height: AppSpacing.xl),
            health.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => EmptyState(
                icon: Icons.cloud_off,
                title: 'Could not load health',
                message: '$e',
                actions: [
                  FilledButton(
                    onPressed: () => ref.invalidate(opsHealthProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
              data: (h) => _HealthSection(health: h),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

// --- KPI tiles ---------------------------------------------------------------

/// Uptime + request-mix headline tiles.
class _MetricsSection extends StatelessWidget {
  final OpsMetrics metrics;
  const _MetricsSection({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final errRate = m.requests.errorRate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Process'),
        const SizedBox(height: AppSpacing.sm),
        _TileGrid(tiles: [
          _Stat('Uptime', _formatUptime(m.process.uptimeS)),
          _Stat('Requests', _compact(m.requests.total),
              caption: _classCaption(m.requests.byClass)),
          _Stat('Error rate', '${(errRate * 100).toStringAsFixed(1)}%',
              severity: _errSeverity(errRate)),
          _Stat('Goroutines', '${m.process.goroutines}',
              caption: 'GOMAXPROCS ${m.process.gomaxprocs}'),
          _Stat('Memory', '${_mb(m.process.memAllocBytes)} MB',
              caption: '${_mb(m.process.memSysBytes)} MB sys'),
          if (m.upstream.placesUpstreamCalls > 0 ||
              m.upstream.placesCacheHits > 0)
            _Stat('Places calls', '${m.upstream.placesUpstreamCalls}',
                caption: '${m.upstream.placesCacheHits} cache hits'),
        ]),
        if (m.requests.routes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Routes'),
          const SizedBox(height: AppSpacing.sm),
          _RouteTable(routes: m.requests.routes),
        ],
      ],
    );
  }

  static String _classCaption(Map<String, int> byClass) {
    final ok = byClass['2xx'] ?? 0;
    final c4 = byClass['4xx'] ?? 0;
    final c5 = byClass['5xx'] ?? 0;
    return '$ok 2xx · $c4 4xx · $c5 5xx';
  }

  static String? _errSeverity(double rate) {
    if (rate >= 0.05) return 'critical';
    if (rate >= 0.02) return 'warn';
    return null;
  }
}

/// Top routes by count. Horizontally scrollable so wide rows never overflow.
class _RouteTable extends StatelessWidget {
  final List<RouteMetric> routes;
  const _RouteTable({required this.routes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sorted = [...routes]..sort((a, b) => b.count.compareTo(a.count));
    final top = sorted.take(12).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: AppSpacing.xl,
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        columns: const [
          DataColumn(label: Text('Route')),
          DataColumn(label: Text('Method')),
          DataColumn(label: Text('Count'), numeric: true),
          DataColumn(label: Text('Error %'), numeric: true),
          DataColumn(label: Text('p95 ms'), numeric: true),
        ],
        rows: [
          for (final r in top)
            DataRow(cells: [
              DataCell(ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(r.route, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(r.method)),
              DataCell(Text('${r.count}')),
              DataCell(Text(
                '${(r.errorRate * 100).toStringAsFixed(1)}%',
                style: r.errorRate >= 0.05
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              )),
              DataCell(Text(r.p95Ms.toStringAsFixed(0))),
            ]),
        ],
      ),
    );
  }
}

// --- Dependencies + backups --------------------------------------------------

class _HealthSection extends StatelessWidget {
  final OpsHealth health;
  const _HealthSection({required this.health});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = health;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (h.degraded) ...[
          _DegradedBanner(reasons: h.reasons),
          const SizedBox(height: AppSpacing.lg),
        ],
        const SectionHeader(title: 'Dependencies'),
        const SizedBox(height: AppSpacing.sm),
        _DependencyRow(
          label: 'Database',
          detail: h.db.status == 'ok' ? '${h.db.pingMs} ms ping' : null,
          pill: _dbPill(theme, h.db),
        ),
        for (final p in h.providers)
          _DependencyRow(
            label: _humanize(p.name),
            detail: p.note.isEmpty ? null : p.note,
            pill: p.configured
                ? _pill(theme, 'configured', 'ok')
                : _pill(theme, 'not configured', 'warn'),
          ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Backups'),
        const SizedBox(height: AppSpacing.sm),
        _DependencyRow(
          label: 'Last backup',
          detail: h.backups.ageS != null
              ? '${_humanizeAge(h.backups.ageS!)} ago'
              : 'no backup recorded',
          pill: _backupPill(theme, h.backups),
        ),
        if (h.build.release.isNotEmpty || h.build.goVersion.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionHeader(title: 'Build'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              if (h.build.release.isNotEmpty) 'release ${h.build.release}',
              if (h.build.goVersion.isNotEmpty) h.build.goVersion,
            ].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  static Widget _dbPill(ThemeData theme, HealthDb db) {
    switch (db.status) {
      case 'ok':
        return _pill(theme, 'ok', 'ok');
      case 'unreachable':
        return _pill(theme, 'unreachable', 'critical');
      default:
        return _pill(theme, 'not configured', 'warn');
    }
  }

  static Widget _backupPill(ThemeData theme, BackupInfo b) {
    if (b.ageS == null) return _pill(theme, 'unknown', 'warn');
    if (b.stale) return _pill(theme, 'stale', 'critical');
    return _pill(theme, 'fresh', 'ok');
  }
}

class _DegradedBanner extends StatelessWidget {
  final List<String> reasons;
  const _DegradedBanner({required this.reasons});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 20, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'System degraded',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final r in reasons)
              Text(
                '• $r',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DependencyRow extends StatelessWidget {
  final String label;
  final String? detail;
  final Widget pill;
  const _DependencyRow({required this.label, this.detail, required this.pill});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          pill,
        ],
      ),
    );
  }
}

// --- Shared helpers ----------------------------------------------------------

/// Severity → pill. ok=green, warn=amber, critical=red (mirrors the Trip
/// Health severity palette).
StatusPill _pill(ThemeData theme, String label, String severity) {
  final (bg, fg) = _severityColors(theme, severity);
  return StatusPill.custom(label: label, background: bg, foreground: fg);
}

(Color, Color) _severityColors(ThemeData theme, String severity) {
  switch (severity) {
    case 'critical':
      return (theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer);
    case 'warn':
      return (Colors.amber.withValues(alpha: 0.20), Colors.amber.shade900);
    case 'ok':
      return (Colors.green.withValues(alpha: 0.15), Colors.green.shade800);
    default:
      return (
        theme.colorScheme.surfaceContainerHighest,
        theme.colorScheme.onSurfaceVariant,
      );
  }
}

String _formatUptime(int seconds) {
  if (seconds <= 0) return '0s';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m';
  return '${seconds}s';
}

/// Seconds → coarse "3d" / "4h" / "5m" / "30s" for the backup age line.
String _humanizeAge(int seconds) {
  if (seconds >= 86400) return '${seconds ~/ 86400}d';
  if (seconds >= 3600) return '${seconds ~/ 3600}h';
  if (seconds >= 60) return '${seconds ~/ 60}m';
  return '${seconds}s';
}

String _compact(int v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return '$v';
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// "google_places" → "Google places".
String _humanize(String name) {
  final s = name.replaceAll('_', ' ');
  return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

// --- Tile primitives (mirrors admin_metrics_screen's _Stat/_TileGrid) --------

class _Stat {
  final String label;
  final String value;
  final String? caption;

  /// Optional severity that tints the value (warn=amber, critical=red).
  final String? severity;
  const _Stat(this.label, this.value, {this.caption, this.severity});
}

class _TileGrid extends StatelessWidget {
  final List<_Stat> tiles;
  const _TileGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final t in tiles)
          Container(
            constraints: const BoxConstraints(minWidth: 140),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: AppRadius.mdAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  t.value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: t.severity == 'critical'
                        ? theme.colorScheme.error
                        : t.severity == 'warn'
                            ? Colors.amber.shade900
                            : null,
                  ),
                ),
                if (t.caption != null)
                  Text(
                    t.caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
