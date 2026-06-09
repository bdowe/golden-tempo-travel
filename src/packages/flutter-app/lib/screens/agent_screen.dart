import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gradient_app_bar.dart';
import '../models/plan_message.dart';
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
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

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

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(planProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  void _loadIntoPlanner() {
    final notifier = ref.read(planProvider.notifier);
    final locations = notifier.completedAsLocations;
    final routeNotifier = ref.read(routeProvider.notifier);
    routeNotifier.clearLocations();
    for (final loc in locations) {
      routeNotifier.addLocation(loc);
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RouteOptimizerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(planProvider);
    final theme = Theme.of(context);

    ref.listen(planProvider, (_, next) {
      if (next.isStreaming || next.streamingText != null) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('AI Travel Agent'),
        actions: [
          if (planState.messages.isNotEmpty || planState.completedLocations != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(planProvider.notifier).reset(),
              tooltip: 'Start over',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: planState.messages.isEmpty && planState.streamingText == null
                ? _EmptyState()
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      for (final msg in planState.messages)
                        _MessageBubble(message: msg),
                      if (planState.streamingText != null && planState.streamingText!.isNotEmpty)
                        _MessageBubble(
                          message: PlanMessage(
                            role: MessageRole.assistant,
                            content: planState.streamingText!,
                          ),
                          isStreaming: true,
                        ),
                      if (planState.activeTools.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Wrap(
                            spacing: 8,
                            children: planState.activeTools.map((tool) {
                              return Chip(
                                avatar: const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                label: Text(_toolLabel(tool)),
                              );
                            }).toList(),
                          ),
                        ),
                      if (planState.completedLocations != null)
                        _ItineraryBanner(
                          summary: planState.completedSummary,
                          locationCount: planState.completedLocations!.length,
                          onLoad: _loadIntoPlanner,
                          onViewTrip: planState.savedTripId == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => TripDetailScreen(tripId: planState.savedTripId!),
                                    ),
                                  ),
                        ),
                      if (planState.error != null)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            planState.error!,
                            style: TextStyle(color: theme.colorScheme.onErrorContainer),
                          ),
                        ),
                    ],
                  ),
          ),
          _InputBar(
            controller: _controller,
            enabled: !planState.isStreaming,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  String _toolLabel(String tool) {
    switch (tool) {
      case 'search_places':
        return 'Searching places...';
      case 'create_itinerary':
        return 'Building itinerary...';
      default:
        return '$tool...';
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: theme.colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Tell me about your dream trip',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'I\'ll search for places and build an itinerary you can load into the route planner.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _SuggestionChip('2 days in Paris'),
                _SuggestionChip('Museums in Rome'),
                _SuggestionChip('Weekend in Tokyo'),
              ],
            ),
          ],
        ),
      ),
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

class _MessageBubble extends StatelessWidget {
  final PlanMessage message;
  final bool isStreaming;

  const _MessageBubble({required this.message, this.isStreaming = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
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
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Itinerary ready — $locationCount locations',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.teal.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (summary != null && summary!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.teal.shade700,
              ),
            ),
          ],
          const SizedBox(height: 12),
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
                  backgroundColor: Colors.teal.shade600,
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                  backgroundColor: Colors.teal.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend() : null,
              decoration: InputDecoration(
                hintText: enabled ? 'Describe your trip...' : 'Thinking...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
