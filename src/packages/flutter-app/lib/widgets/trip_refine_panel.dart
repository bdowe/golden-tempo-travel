import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../providers/plan_provider.dart';
import 'chat_panel.dart';

/// Which slice of the itinerary an AI refinement session targets. Mirrors the
/// server tool's section selector: one day (optionally qualified by city,
/// since day numbers repeat across cities in legacy trips), one city/hub, or
/// the whole trip.
class RefineTarget {
  final String scope; // 'trip' | 'day' | 'city'
  final int? day;
  final String? city;

  /// General-purpose "Trip assistant" flavor: same whole-trip scope, but the
  /// framing invites questions rather than assuming every message is an edit.
  final bool assistant;

  const RefineTarget._(this.scope, this.day, this.city,
      {this.assistant = false});
  const RefineTarget.trip() : this._('trip', null, null);
  const RefineTarget.assistant() : this._('trip', null, null, assistant: true);
  const RefineTarget.day(int day, {String? city}) : this._('day', day, city);
  const RefineTarget.city(String city) : this._('city', null, city);

  /// Canonical **English** section name. This is embedded verbatim in the
  /// refine seed prompt sent to the agent (`trip_detail_screen.dart`), so it is
  /// never localized — see [displayLabel] for the user-facing equivalent
  /// (specs/i18n-spanish).
  String get label {
    switch (scope) {
      case 'day':
        return city == null ? 'Day $day' : 'Day $day — $city';
      case 'city':
        return city!;
      default:
        return 'Whole trip';
    }
  }

  /// Localized twin of [label], for anything the user reads.
  String displayLabel(AppLocalizations l10n) {
    switch (scope) {
      case 'day':
        return city == null
            ? l10n.refineTargetDay(day!)
            : l10n.refineTargetDayCity(day!, city!);
      case 'city':
        return city!;
      default:
        return l10n.refineTargetWholeTrip;
    }
  }
}

/// The in-page AI refinement chat for one trip, shown beside (wide layouts) or
/// over (bottom sheet) the trip detail page. Drives the per-trip
/// [tripRefineProvider] session and calls [onTripUpdated] whenever the server
/// reports the trip was patched in place, so the host screen can reload.
class TripRefinePanel extends ConsumerWidget {
  final String tripId;
  final RefineTarget target;
  final VoidCallback onClose;
  final VoidCallback onTripUpdated;

  const TripRefinePanel({
    super.key,
    required this.tripId,
    required this.target,
    required this.onClose,
    required this.onTripUpdated,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    ref.listen(tripRefineProvider(tripId).select((s) => s.tripUpdateCount),
        (prev, next) {
      if (next > (prev ?? 0)) onTripUpdated();
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Icon(
                target.assistant
                    ? Icons.chat_bubble_outline
                    : Icons.auto_awesome,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  target.assistant
                      ? l10n.refineAssistantTitle
                      : l10n.refineHeader(target.displayLabel(l10n)),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.commonClose,
                onPressed: onClose,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ChatPanel(
            state: tripRefineProvider(tripId),
            notifier: tripRefineProvider(tripId).notifier,
            inputHint: target.assistant
                ? l10n.refineAssistantHint
                : l10n.refineHint,
          ),
        ),
      ],
    );
  }
}
