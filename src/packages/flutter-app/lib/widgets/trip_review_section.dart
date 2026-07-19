import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trip_finding.dart';
import '../providers/trip_review_provider.dart';
import '../theme/spacing.dart';
import 'empty_state.dart';
import 'section_header.dart';
import 'status_pill.dart';

/// The trip-detail "Trip health" section: surfaces the read-only review from
/// `GET /trips/{id}/review` as an ordered list of findings, worst-severity
/// first. Self-contained — it owns its data via [tripReviewProvider], keyed on
/// (tripId, checkHours). Mirrors [ChecklistSection]/[BudgetSection] structure.
///
/// Tapping a finding with a resolvable day deep-links the itinerary to that day
/// via [onScrollToDay]; [dayForItem] resolves an item id → day when a finding
/// carries only an item id. Both are optional (no-op when absent/unresolvable).
class TripReviewSection extends ConsumerStatefulWidget {
  final String tripId;
  final bool isOffline;

  /// Scrolls the itinerary to [day]. Wired to the screen's `_scrollToDay`.
  final void Function(int day)? onScrollToDay;

  /// Resolves an itinerary item id to its day, for findings that carry an
  /// item id but no day. Returns null when the item isn't placed on a day.
  final int? Function(String itemId)? dayForItem;

  const TripReviewSection({
    super.key,
    required this.tripId,
    required this.isOffline,
    this.onScrollToDay,
    this.dayForItem,
  });

  @override
  ConsumerState<TripReviewSection> createState() => _TripReviewSectionState();
}

// Severity display order (worst first) and rank for sorting.
const Map<String, int> _severityRank = {
  'critical': 0,
  'warn': 1,
  'info': 2,
};

const Map<String, String> _severityLabels = {
  'critical': 'Critical',
  'warn': 'Warning',
  'info': 'Info',
};

const Map<String, IconData> _categoryIcons = {
  'dates': Icons.event_outlined,
  'unscheduled': Icons.schedule_outlined,
  'packing': Icons.luggage_outlined,
  'lodging': Icons.hotel_outlined,
  'transit': Icons.directions_transit_outlined,
  'budget': Icons.account_balance_wallet_outlined,
  'bookings': Icons.confirmation_number_outlined,
};

int _rankOf(String severity) => _severityRank[severity] ?? 3;

class _TripReviewSectionState extends ConsumerState<TripReviewSection> {
  // Opt-in opening-hours check: flips the provider key to the slower variant.
  bool _checkHours = false;

  TripReviewKey get _key =>
      TripReviewKey(widget.tripId, checkHours: _checkHours);

  // Severity → chip colors. Critical reads loud (red), warn amber, info neutral.
  ({Color bg, Color fg}) _severityColors(ThemeData theme, String severity) {
    switch (severity) {
      case 'critical':
        return (
          bg: theme.colorScheme.errorContainer,
          fg: theme.colorScheme.onErrorContainer,
        );
      case 'warn':
        return (
          bg: Colors.amber.withValues(alpha: 0.20),
          fg: Colors.amber.shade900,
        );
      default:
        return (
          bg: theme.colorScheme.surfaceContainerHighest,
          fg: theme.colorScheme.onSurfaceVariant,
        );
    }
  }

  void _onTapFinding(TripFinding finding) {
    final onScrollToDay = widget.onScrollToDay;
    if (onScrollToDay == null) return;
    int? day = finding.day;
    if (day == null && finding.itemId != null) {
      day = widget.dayForItem?.call(finding.itemId!);
    }
    if (day != null) onScrollToDay(day);
  }

  void _toggleCheckHours() {
    if (widget.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("You're offline — reconnect to run more checks.")),
      );
      return;
    }
    setState(() => _checkHours = !_checkHours);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tripReviewProvider(_key));
    // Best-effort: on error or first load with no data, render nothing rather
    // than an error state — a utility section shouldn't shout. (Offline still
    // shows the last-loaded findings — the read GET is cached by the family.)
    final findings = async.valueOrNull;
    if (findings == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final sorted = [...findings]
      ..sort((a, b) => _rankOf(a.severity).compareTo(_rankOf(b.severity)));
    final worst = sorted.isEmpty ? null : sorted.first.severity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        SectionHeader(
          title: 'Trip health',
          action: findings.isEmpty
              ? null
              : StatusPill.custom(
                  label: '${findings.length} to review',
                  background: _severityColors(theme, worst!).bg,
                  foreground: _severityColors(theme, worst).fg,
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (findings.isEmpty)
          const EmptyState(
            compact: true,
            icon: Icons.check_circle_outline,
            iconColor: Colors.green,
            title: 'Looks good',
            message: 'No issues found — your trip is in good shape.',
          )
        else
          for (final f in sorted) _buildRow(theme, f),
        const SizedBox(height: AppSpacing.sm),
        _buildCheckHoursAction(theme, async.isLoading),
      ],
    );
  }

  Widget _buildRow(ThemeData theme, TripFinding finding) {
    final colors = _severityColors(theme, finding.severity);
    final icon = _categoryIcons[finding.category] ?? Icons.info_outline;
    // A finding is tappable when we can resolve it to a day to scroll to.
    final tappable = widget.onScrollToDay != null &&
        (finding.day != null ||
            (finding.itemId != null &&
                widget.dayForItem?.call(finding.itemId!) != null));
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill.custom(
            label: _severityLabels[finding.severity] ?? finding.severity,
            background: colors.bg,
            foreground: colors.fg,
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              finding.message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurface),
            ),
          ),
          if (tappable)
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
    if (!tappable) return row;
    return InkWell(
      key: ValueKey('finding-${finding.category}-${finding.message}'),
      onTap: () => _onTapFinding(finding),
      borderRadius: AppRadius.smAll,
      child: row,
    );
  }

  Widget _buildCheckHoursAction(ThemeData theme, bool loading) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(_checkHours ? Icons.check : Icons.access_time),
        label: Text(_checkHours
            ? 'Opening hours checked'
            : 'Also check opening hours'),
        onPressed:
            (widget.isOffline || _checkHours) ? null : _toggleCheckHours,
      ),
    );
  }
}
