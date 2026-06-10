import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/flight_offer.dart';
import '../models/plan_message.dart';
import '../providers/plan_provider.dart';
import 'flight_offer_card.dart';

/// The plan-agent chat surface (messages, tool chips, flight cards, input bar)
/// decoupled from any screen, so the full-screen Agent tab and the trip-detail
/// refine panel share one implementation. The provider pair is passed in:
/// AgentScreen hands the global [planProvider], the refine panel hands its
/// per-trip [tripRefineProvider] instance.
class ChatPanel extends ConsumerStatefulWidget {
  final ProviderListenable<PlanState> state;
  final ProviderListenable<PlanNotifier> notifier;
  final String inputHint;

  /// Shown instead of the message list while the conversation is empty.
  final Widget? emptyState;

  /// Optional extra content rendered after the messages (e.g. the Agent tab's
  /// completed-itinerary banner).
  final Widget Function(BuildContext context, PlanState state)? footerBuilder;

  const ChatPanel({
    super.key,
    required this.state,
    required this.notifier,
    this.inputHint = 'Describe your trip...',
    this.emptyState,
    this.footerBuilder,
  });

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  /// Autoscroll follows the stream only while the user is at the bottom;
  /// scrolling up to re-read pauses it until they return to the bottom.
  bool _stickToBottom = true;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_stickToBottom && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Only UserScrollNotification flips the flag off — the programmatic
  // animateTo also moves the position, and may be mid-flight (away from the
  // bottom) when the next stream chunk arrives.
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward) {
      _stickToBottom = false;
    } else if (notification is ScrollUpdateNotification) {
      final position = notification.metrics;
      if (position.pixels >= position.maxScrollExtent - 50) {
        _stickToBottom = true;
      }
    }
    return false;
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    ref.read(widget.notifier).sendMessage(text);
    _stickToBottom = true;
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final planState = ref.watch(widget.state);
    final theme = Theme.of(context);

    ref.listen(widget.state, (_, next) {
      if (next.isStreaming || next.streamingText != null) {
        _scrollToBottom();
      }
    });

    return Column(
      children: [
        Expanded(
          child: planState.messages.isEmpty && planState.streamingText == null
              ? (widget.emptyState ?? const SizedBox.shrink())
              : NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      for (final msg in planState.messages)
                        ChatMessageBubble(message: msg),
                      if (planState.streamingText != null && planState.streamingText!.isNotEmpty)
                        ChatMessageBubble(
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
                      if (planState.flightOffers != null && planState.flightOffers!.isNotEmpty)
                        _FlightOptions(
                          routeLabel: planState.flightRouteLabel,
                          offers: planState.flightOffers!,
                        ),
                      if (widget.footerBuilder != null)
                        widget.footerBuilder!(context, planState),
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
        ),
        _InputBar(
          controller: _controller,
          enabled: !planState.isStreaming,
          hint: widget.inputHint,
          onSend: _send,
        ),
      ],
    );
  }

  String _toolLabel(String tool) {
    switch (tool) {
      case 'search_places':
        return 'Searching places...';
      case 'create_itinerary':
        return 'Building itinerary...';
      case 'update_itinerary_section':
        return 'Updating itinerary...';
      case 'search_flights':
        return 'Searching flights...';
      default:
        return '$tool...';
    }
  }
}

class ChatMessageBubble extends StatelessWidget {
  final PlanMessage message;
  final bool isStreaming;

  const ChatMessageBubble({super.key, required this.message, this.isStreaming = false});

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

/// Inline flight results in the chat — a header plus the agent's top ranked
/// options as shared FlightOfferCards (first = best match).
class _FlightOptions extends StatelessWidget {
  final String? routeLabel;
  final List<FlightOffer> offers;

  const _FlightOptions({required this.routeLabel, required this.offers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = (routeLabel == null || routeLabel!.trim().isEmpty)
        ? 'Flight options'
        : 'Flight options · $routeLabel';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(12),
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
              Icon(Icons.flight, color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < offers.length; i++)
            FlightOfferCard(offer: offers[i], isBest: i == 0),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.hint,
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
                hintText: enabled ? hint : 'Thinking...',
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
