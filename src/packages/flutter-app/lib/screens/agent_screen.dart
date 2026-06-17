import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(planProvider);

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('Plan your trip'),
        actions: [
          if (planState.messages.isNotEmpty || planState.completedLocations != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(planProvider.notifier).reset(),
              tooltip: 'Start over',
            ),
          const AccountMenu(),
        ],
      ),
      body: ChatPanel(
        state: planProvider,
        notifier: planProvider.notifier,
        emptyState: _EmptyState(),
        footerBuilder: (context, state) => state.completedLocations == null
            ? const SizedBox.shrink()
            : _ItineraryBanner(
                summary: state.completedSummary,
                locationCount: state.completedLocations!.length,
                onLoad: _loadIntoPlanner,
                onViewTrip: state.savedTripId == null
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TripDetailScreen(tripId: state.savedTripId!),
                          ),
                        ),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.chat_bubble_outline,
      title: 'Tell me about your dream trip',
      message:
          "I'll search for places and build an itinerary you can load into the route planner.",
      actions: [
        _SuggestionChip('2 days in Paris'),
        _SuggestionChip('Museums in Rome'),
        _SuggestionChip('Weekend in Tokyo'),
      ],
    );
  }
}

class _SuggestionChip extends ConsumerWidget {
  final String text;
  const _SuggestionChip(this.text);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      label: Text(text),
      onPressed: () => ref.read(planProvider.notifier).sendMessage(text),
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
                  'Itinerary ready — $locationCount locations',
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
          // When the trip was saved, opening it is the primary action (it has the
          // full itinerary, bookings, etc.); loading into the route planner stays
          // available as a secondary option. Anonymous sessions have no saved
          // trip, so the planner is their only action.
          if (onViewTrip != null) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onViewTrip,
                icon: const Icon(Icons.luggage),
                label: const Text('View trip'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandLight,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onLoad,
                icon: const Icon(Icons.map),
                label: const Text('Load into route planner'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onLoad,
                icon: const Icon(Icons.map),
                label: const Text('Load into Planner'),
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
