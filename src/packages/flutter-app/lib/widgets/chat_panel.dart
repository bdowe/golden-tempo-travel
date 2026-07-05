import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/plan_message.dart';
import '../providers/plan_provider.dart';
import '../theme/app_colors.dart';
import 'result_summary_chip.dart';

/// The plan-agent chat surface (messages, tool chips, result chips, input bar)
/// decoupled from any screen, so the full-screen Agent tab and the trip-detail
/// refine panel share one implementation. The provider pair is passed in:
/// AgentScreen hands the global [planProvider], the refine panel hands its
/// per-trip [tripRefineProvider] instance.
///
/// Streamed tokens arrive many times per frame, so the widget tree is split so
/// a token flush rebuilds only the streaming bubble: committed messages live in
/// a keyed ListView.builder, and the live tail (_ChatTail) is a column of leaf
/// widgets each watching a narrow select of PlanState.
class ChatPanel extends ConsumerStatefulWidget {
  final ProviderListenable<PlanState> state;
  final ProviderListenable<PlanNotifier> notifier;
  final String inputHint;

  /// Shown instead of the message list while the conversation is empty.
  final Widget? emptyState;

  /// Optional extra content rendered after the messages (e.g. the Agent tab's
  /// completed-itinerary banner).
  final Widget Function(BuildContext context, PlanState state)? footerBuilder;

  /// When set, result summary chips (flights, events, local picks, ferries)
  /// become tappable once a trip id exists and open that trip. The refine
  /// panel leaves this null — the trip is already on screen.
  final void Function(String tripId)? onViewTrip;

  const ChatPanel({
    super.key,
    required this.state,
    required this.notifier,
    this.inputHint = 'Describe your trip...',
    this.emptyState,
    this.footerBuilder,
    this.onViewTrip,
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

  /// At most one bottom-jump pending per frame, no matter how many state
  /// changes request one.
  bool _scrollScheduled = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (_stickToBottom && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  // Only UserScrollNotification flips the flag off — the programmatic jumpTo
  // emits only ScrollUpdateNotifications, so it can't disarm itself.
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
    final messages = ref.watch(widget.state.select((s) => s.messages));
    final isStreaming = ref.watch(widget.state.select((s) => s.isStreaming));
    final isEmpty = ref.watch(widget.state
        .select((s) => s.messages.isEmpty && s.streamingText == null));

    ref.listen(widget.state.select((s) => s.streamingText),
        (_, __) => _scrollToBottom());
    ref.listen(widget.state.select((s) => s.messages.length),
        (_, __) => _scrollToBottom());

    return Column(
      children: [
        Expanded(
          child: isEmpty
              ? (widget.emptyState ?? const SizedBox.shrink())
              : NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length + 1,
                    itemBuilder: (context, i) {
                      if (i < messages.length) {
                        // Append-only list, so index keys are stable.
                        return ChatMessageBubble(
                          key: ValueKey('msg-$i'),
                          message: messages[i],
                        );
                      }
                      return _ChatTail(
                        key: const ValueKey('chat-tail'),
                        state: widget.state,
                        notifier: widget.notifier,
                        footerBuilder: widget.footerBuilder,
                        onViewTrip: widget.onViewTrip,
                      );
                    },
                  ),
                ),
        ),
        _InputBar(
          controller: _controller,
          enabled: !isStreaming,
          hint: widget.inputHint,
          onSend: _send,
        ),
      ],
    );
  }
}

/// Everything below the committed messages — the live streaming bubble, tool
/// chips, result chips, footer, and error banner. Each child watches its own
/// narrow select so a token flush rebuilds only [_StreamingBubble].
class _ChatTail extends StatelessWidget {
  final ProviderListenable<PlanState> state;
  final ProviderListenable<PlanNotifier> notifier;
  final Widget Function(BuildContext context, PlanState state)? footerBuilder;
  final void Function(String tripId)? onViewTrip;

  const _ChatTail({
    super.key,
    required this.state,
    required this.notifier,
    required this.footerBuilder,
    required this.onViewTrip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StreamingBubble(state: state),
        _ActiveToolChips(state: state),
        _ProfileNoteChip(state: state),
        _ResultChips(state: state, notifier: notifier, onViewTrip: onViewTrip),
        if (footerBuilder != null)
          _ChatFooter(state: state, footerBuilder: footerBuilder!),
        _ErrorBanner(state: state),
      ],
    );
  }
}

class _StreamingBubble extends ConsumerWidget {
  final ProviderListenable<PlanState> state;

  const _StreamingBubble({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(state.select((s) => s.streamingText));
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return ChatMessageBubble(
      message: PlanMessage(role: MessageRole.assistant, content: text),
      isStreaming: true,
    );
  }
}

class _ActiveToolChips extends ConsumerWidget {
  final ProviderListenable<PlanState> state;

  const _ActiveToolChips({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTools = ref.watch(state.select((s) => s.activeTools));
    if (activeTools.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        children: activeTools.map((tool) {
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
    );
  }

  static String _toolLabel(String tool) {
    switch (tool) {
      case 'search_places':
        return 'Searching places...';
      case 'create_itinerary':
        return 'Building itinerary...';
      case 'update_itinerary_section':
        return 'Updating itinerary...';
      case 'search_flights':
        return 'Searching flights...';
      case 'search_events':
        return 'Finding events...';
      case 'suggest_ferries':
        return 'Finding ferries...';
      default:
        return '$tool...';
    }
  }
}

class _ProfileNoteChip extends ConsumerWidget {
  final ProviderListenable<PlanState> state;

  const _ProfileNoteChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(state.select((s) => s.profileUpdateNote));
    if (note == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: note.isEmpty ? 'Travel profile updated' : note,
          child: Chip(
            avatar: Icon(Icons.check_circle_outline,
                size: 16, color: theme.colorScheme.primary),
            label: const Text('Noted — travel profile updated'),
          ),
        ),
      ),
    );
  }
}

/// One quiet summary line per result set the agent found. The full results
/// live on the trip detail screen (booking checklist, embedded events,
/// itinerary pins), so the chat only names what arrived and links there.
class _ResultChips extends ConsumerWidget {
  final ProviderListenable<PlanState> state;
  final ProviderListenable<PlanNotifier> notifier;
  final void Function(String tripId)? onViewTrip;

  const _ResultChips({
    required this.state,
    required this.notifier,
    required this.onViewTrip,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Record equality compares the lists by identity, which works because the
    // provider replaces each list whole on its SSE event — never mutates one
    // in place. In-place mutation would silently stop chip updates.
    final r = ref.watch(state.select((s) => (
          flights: s.flightOffers,
          flightRoute: s.flightRouteLabel,
          localRecs: s.localRecs,
          localRecsCity: s.localRecsCity,
          events: s.eventResults,
          eventsCity: s.eventsCityLabel,
          ferries: s.ferryOptions,
          ferryRoute: s.ferryRouteLabel,
          eventLinks: s.eventLinks,
          eventLinksCity: s.eventLinksCity,
          savedTripId: s.savedTripId,
        )));

    // Agent-tab chips are plain labels until `done` delivers savedTripId,
    // then flip tappable; the refine panel passes no onViewTrip at all.
    final tripId = r.savedTripId ?? ref.read(notifier).tripId;
    final onTap = (onViewTrip != null && tripId != null)
        ? () => onViewTrip!(tripId)
        : null;

    String label(int count, String singular, String plural, String? suffix) {
      final base = '$count ${count == 1 ? singular : plural}';
      return (suffix == null || suffix.trim().isEmpty) ? base : '$base · $suffix';
    }

    final chips = <Widget>[
      if (r.flights != null && r.flights!.isNotEmpty)
        ResultSummaryChip(
          icon: Icons.flight,
          accent: AppColors.toolFlights,
          label: label(r.flights!.length, 'flight option', 'flight options',
              r.flightRoute),
          onTap: onTap,
        ),
      if (r.localRecs != null && r.localRecs!.isNotEmpty)
        ResultSummaryChip(
          icon: Icons.verified,
          accent: AppColors.toolLocal,
          label: label(r.localRecs!.length, 'local pick', 'local picks',
              r.localRecsCity),
          onTap: onTap,
        ),
      if (r.events != null && r.events!.isNotEmpty)
        ResultSummaryChip(
          icon: Icons.local_activity,
          accent: AppColors.toolEvents,
          label: label(r.events!.length, 'event', 'events', r.eventsCity),
          onTap: onTap,
        ),
      if (r.ferries != null && r.ferries!.isNotEmpty)
        ResultSummaryChip(
          icon: Icons.directions_boat,
          accent: AppColors.toolFerries,
          label: label(r.ferries!.length, 'ferry option', 'ferry options',
              r.ferryRoute),
          onTap: onTap,
        ),
      if (r.eventLinks != null && r.eventLinks!.isNotEmpty)
        ResultSummaryChip(
          icon: Icons.link,
          accent: AppColors.toolEvents,
          label: label(r.eventLinks!.length, 'event source', 'event sources',
              r.eventLinksCity),
          onTap: onTap,
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: chips),
    );
  }
}

/// Bridges the whole-state `footerBuilder(context, state)` contract into the
/// select-based tail. Watching the full state here is fine — this leaf is
/// nearly empty until the itinerary completes.
class _ChatFooter extends ConsumerWidget {
  final ProviderListenable<PlanState> state;
  final Widget Function(BuildContext context, PlanState state) footerBuilder;

  const _ChatFooter({required this.state, required this.footerBuilder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planState = ref.watch(state);
    return footerBuilder(context, planState);
  }
}

class _ErrorBanner extends ConsumerWidget {
  final ProviderListenable<PlanState> state;

  const _ErrorBanner({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(state.select((s) => s.error));
    if (error == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        error,
        style: TextStyle(color: theme.colorScheme.onErrorContainer),
      ),
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  final PlanMessage message;
  final bool isStreaming;

  const ChatMessageBubble({super.key, required this.message, this.isStreaming = false});

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

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
              child: isUser
                  ? Text(
                      message.content,
                      style: TextStyle(color: theme.colorScheme.onPrimary),
                    )
                  : GptMarkdown(
                      message.content,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      onLinkTap: (url, title) => _openLink(url),
                    ),
            ),
            if (isStreaming) ...[
              const SizedBox(width: 6),
              const _StreamingCursor(),
            ],
          ],
        ),
      ),
    );
  }
}

/// A softly blinking caret shown at the end of the live streaming bubble —
/// quieter than a spinner.
class _StreamingCursor extends StatefulWidget {
  const _StreamingCursor();

  @override
  State<_StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<_StreamingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _controller.drive(Tween(begin: 0.15, end: 0.7)),
      child: Container(
        width: 2.5,
        height: 16,
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface,
          borderRadius: BorderRadius.circular(1.25),
        ),
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
            color: Colors.black.withValues(alpha: 0.06),
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
