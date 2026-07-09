import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/admin_metrics.dart';
import '../providers/admin_metrics_provider.dart';
import '../theme/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_container.dart';
import '../widgets/section_header.dart';

/// Growth metrics dashboard (admin-only; the API enforces adminMiddleware).
/// Stat tiles over the Phase-1 funnel from docs/business-model.md §8 —
/// activation, attach rate, retention, AI cost — plus the alerts counters.
/// Deliberately chartless: every number here is a headline, not a trend.
class AdminMetricsScreen extends ConsumerStatefulWidget {
  const AdminMetricsScreen({super.key});

  @override
  ConsumerState<AdminMetricsScreen> createState() =>
      _AdminMetricsScreenState();
}

class _AdminMetricsScreenState extends ConsumerState<AdminMetricsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(adminMetricsProvider(_days));

    return Scaffold(
      appBar: AppBar(title: const Text('Metrics')),
      body: PageContainer(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 30, label: Text('30 days')),
                  ButtonSegment(value: 90, label: Text('90 days')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
            ),
            Expanded(
              child: metrics.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => EmptyState(
                  icon: Icons.cloud_off,
                  title: 'Could not load metrics',
                  message: '$e',
                  actions: [
                    FilledButton(
                      onPressed: () =>
                          ref.invalidate(adminMetricsProvider(_days)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
                data: (m) => _MetricsBody(metrics: m),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricsBody extends StatelessWidget {
  final AdminMetrics metrics;
  const _MetricsBody({required this.metrics});

  String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

  String _tokens(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }

  String _usd(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SectionHeader(title: 'Funnel'),
        const SizedBox(height: AppSpacing.sm),
        _TileGrid(tiles: [
          // Hidden (not zero) when the API predates landing_views — null
          // means "old API", 0 means "no views".
          if (m.landingViews != null)
            _Stat('Landing views', '${m.landingViews}',
                caption: 'directional — anonymous, rate-limit bounded'),
          _Stat('Signups', '${m.signups}'),
          _Stat('Activated', '${m.activatedSignups}',
              caption: _pct(m.activationRate)),
          _Stat('Onboardings', '${m.onboardingsCompleted}'),
          _Stat('Second-trip retention', '${m.secondTripRetention}',
              caption: '≥2 trips ≥7 days apart'),
          _Stat('Multi-day planners', '${m.sessionFrequencyReturning}',
              caption: 'sessions on ≥2 days'),
        ]),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Trips & bookings'),
        const SizedBox(height: AppSpacing.sm),
        _TileGrid(tiles: [
          _Stat('Trips created', '${m.tripsCreated}'),
          _Stat('Trips refined', '${m.tripsRefined}'),
          _Stat('Attach rate', _pct(m.attachRate),
              caption: '${m.tripsWithBookingClick} trips w/ click'),
          // The anonymous share (signed-out clicks, rate-limit bounded but
          // unaudited) rides as a caption so partner-facing reads can
          // discount it; caption absent on APIs that predate the split.
          _Stat('Booking clicks', '${m.bookingClicks}',
              caption: m.bookingClicksAnonymous != null
                  ? '${m.bookingClicksAnonymous} anonymous'
                  : null),
          _Stat('Marked booked', '${m.todosMarkedBooked}'),
        ]),
        if (m.clicksByProvider.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _ProviderClicks(clicks: m.clicksByProvider),
        ],
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'AI planning'),
        const SizedBox(height: AppSpacing.sm),
        _TileGrid(tiles: [
          _Stat('Active users (MAU)', '${m.activeUsers}'),
          _Stat('Est. cost / active user', _usd(m.estCogsPerActiveUser),
              caption: 'Claude only, estimate'),
          _Stat('Plan sessions', '${m.planSessions}',
              caption: '${m.planSessionsAnonymous} anonymous'),
          _Stat('Agent loop cap hits', '${m.agentLoopCapHits}',
              caption: 'runaway-loop signal'),
          _Stat('Would hit plan cap', '${m.freeCapWouldHits['plan_runs'] ?? 0}',
              caption:
                  '${m.freeCapUsersAffected['plan_runs'] ?? 0} users affected'),
          _Stat(
              'Would hit trip cap', '${m.freeCapWouldHits['active_trips'] ?? 0}',
              caption:
                  '${m.freeCapUsersAffected['active_trips'] ?? 0} users affected'),
          _Stat('Tokens in', _tokens(m.planInputTokens),
              caption: '${_tokens(m.planCacheReadTokens)} from cache'),
          _Stat('Tokens out', _tokens(m.planOutputTokens),
              caption: 'est. ${_usd(m.estClaudeCostUsd)} total'),
        ]),
        if (m.placesCallsSinceProcessStart != null ||
            m.eventsCallsSinceProcessStart != null) ...[
          const SizedBox(height: AppSpacing.xl),
          // Deliberately labeled "(since restart)": these counters are
          // process-lifetime on the API and reset on every deploy — they are
          // NOT scoped to the selected window above.
          const SectionHeader(title: 'Provider APIs (since restart)'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Process-lifetime counters — reset on API restart, '
            'not scoped to the selected window.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _TileGrid(tiles: [
            if (m.placesCallsSinceProcessStart != null) ...[
              _Stat(
                'Places API (since restart)',
                '${m.placesCallsSinceProcessStart!.totalUpstream}',
                caption:
                    '${m.placesCallsSinceProcessStart!.totalCacheHits} cache hits'
                    ' · est. ${_usd(m.placesCallsSinceProcessStart!.estPlacesCostUsd)}',
              ),
              _Stat(
                'Places by class',
                '${m.placesCallsSinceProcessStart!.search.upstream} search',
                caption:
                    '${m.placesCallsSinceProcessStart!.autocomplete.upstream} autocomplete'
                    ' · ${m.placesCallsSinceProcessStart!.details.upstream} details',
              ),
            ],
            if (m.eventsCallsSinceProcessStart != null)
              _Stat(
                'Events API (since restart)',
                '${m.eventsCallsSinceProcessStart!.upstream}',
                caption:
                    '${m.eventsCallsSinceProcessStart!.cacheHits} cache hits · free tier',
              ),
          ]),
        ],
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader(title: 'Price alerts'),
        const SizedBox(height: AppSpacing.sm),
        _TileGrid(tiles: [
          _Stat('Created', '${m.alertsCreated}'),
          _Stat('Triggered', '${m.alertsTriggered}'),
        ]),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

class _Stat {
  final String label;
  final String value;
  final String? caption;
  const _Stat(this.label, this.value, {this.caption});
}

/// Responsive tile row: fixed-min-width tiles that wrap. Values wear text
/// tokens (never a series color) per the dataviz rules — these are headline
/// numbers, not encoded marks.
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

/// Booking clicks by provider: labeled rows with a single-hue proportional
/// bar. One hue on purpose — the bars encode magnitude, the labels carry
/// identity, so no categorical palette is needed.
class _ProviderClicks extends StatelessWidget {
  final Map<String, int> clicks;
  const _ProviderClicks({required this.clicks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = clicks.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clicks by provider', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    e.key,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 10,
                        width: max == 0
                            ? 0
                            : constraints.maxWidth * (e.value / max),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${e.value}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
