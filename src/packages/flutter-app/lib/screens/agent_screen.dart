import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../widgets/account_menu.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/chat_panel.dart';
import '../widgets/empty_state.dart';
import '../providers/plan_provider.dart';
import '../providers/route_provider.dart';
import 'route_optimizer_screen.dart';
import 'trip_detail_screen.dart';

class AgentScreen extends ConsumerStatefulWidget {
  final String? initialMessage;

  /// When set (with [initialMessage]), reopens an existing trip for refinement:
  /// the conversation is bound to this chat group so new itineraries append as
  /// versions of that trip rather than creating a duplicate.
  final String? chatId;

  const AgentScreen({super.key, this.initialMessage, this.chatId});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final notifier = ref.read(planProvider.notifier);
        if (widget.chatId != null) {
          notifier.beginRefinement(chatId: widget.chatId!, seedMessage: widget.initialMessage!);
        } else {
          notifier.sendMessage(widget.initialMessage!);
        }
      });
    }
  }

  void _loadIntoPlanner() {
    final notifier = ref.read(planProvider.notifier);
    final locations = notifier.completedAsLocations;
    final routeNotifier = ref.read(routeProvider.notifier);
    routeNotifier.clearLocations();
    for (final loc in locations) {
      routeNotifier.addLocation(loc);
    }
    // Push (not replace) so the chat stays beneath the planner in this tab's
    // stack — back returns to the conversation.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RouteOptimizerScreen()),
    );
  }

  void _openTrip(String tripId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: tripId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Narrow select so streaming-text flushes don't rebuild the Scaffold.
    final showReset = ref.watch(planProvider.select(
        (s) => s.messages.isNotEmpty || s.completedLocations != null));
    final l10n = context.l10n;

    return Scaffold(
      appBar: GradientAppBar(
        title: Text(l10n.agentScreenTitle),
        actions: [
          if (showReset)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(planProvider.notifier).reset(),
              tooltip: l10n.agentScreenStartOver,
            ),
          const AccountMenu(),
        ],
      ),
      body: ChatPanel(
        state: planProvider,
        notifier: planProvider.notifier,
        emptyState: _EmptyState(),
        onViewTrip: _openTrip,
        footerBuilder: (context, state) => state.completedLocations == null
            ? const SizedBox.shrink()
            : _ItineraryBanner(
                summary: state.completedSummary,
                locationCount: state.completedLocations!.length,
                onLoad: _loadIntoPlanner,
                onViewTrip: state.savedTripId == null
                    ? null
                    : () => _openTrip(state.savedTripId!),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EmptyState(
      icon: Icons.chat_bubble_outline,
      title: l10n.agentScreenEmptyTitle,
      message: l10n.agentScreenEmptyMessage,
      actions: [
        _SuggestionChip(l10n.agentScreenSuggestionParis),
        _SuggestionChip(l10n.agentScreenSuggestionRome),
        _SuggestionChip(l10n.agentScreenSuggestionTokyo),
      ],
    );
  }
}

/// A one-tap conversation starter. The localized text is BOTH what the user
/// reads and what gets sent: it becomes a message in the traveler's own
/// transcript, so an English message they never wrote would read as a bug. The
/// agent answers in the traveler's language anyway (specs/i18n-spanish). This
/// matches the home screen's suggestion chips.
class _SuggestionChip extends ConsumerWidget {
  final String prompt;
  const _SuggestionChip(this.prompt);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      label: Text(prompt),
      onPressed: () => ref.read(planProvider.notifier).sendMessage(prompt),
    );
  }
}

class _ItineraryBanner extends StatelessWidget {
  final String? summary;
  final int locationCount;
  final VoidCallback onLoad;
  final VoidCallback? onViewTrip;

  const _ItineraryBanner({
    this.summary,
    required this.locationCount,
    required this.onLoad,
    this.onViewTrip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('itinerary-banner'),
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      // Tint fill (no border) separates this from the chat — spacing/tint over
      // borders.
      decoration: BoxDecoration(
        color: AppColors.brandTint,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.brand, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.l10n.agentScreenItineraryReady(locationCount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.brandDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (summary != null && summary!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              summary!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.brandDark.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // When the trip was saved, opening it is the one action — the full
          // itinerary, bookings, and map all live there. Anonymous sessions
          // have no saved trip, so the route planner is their only action.
          if (onViewTrip != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onViewTrip,
                icon: const Icon(Icons.luggage),
                label: Text(context.l10n.agentScreenViewTrip),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandLight,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLoad,
                icon: const Icon(Icons.map),
                label: Text(context.l10n.agentScreenLoadIntoPlanner),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandLight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
