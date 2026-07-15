import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/plan_message.dart';
import '../providers/dictation_provider.dart';
import '../providers/plan_provider.dart';
import '../services/dictation_controller.dart';
import '../theme/app_colors.dart';
import '../utils/tracked_launch.dart';
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

  /// Voice dictation for this composer (specs/voice-dictation): writes
  /// transcripts into [_controller]; the user reviews and sends normally.
  late final DictationController _dictation;

  /// Autoscroll follows the stream only while the user is at the bottom;
  /// scrolling up to re-read pauses it until they return to the bottom.
  bool _stickToBottom = true;

  /// At most one bottom-jump pending per frame, no matter how many state
  /// changes request one.
  bool _scrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _dictation = ref.read(dictationControllerFactoryProvider)(_controller);
    _dictation.addListener(_onDictationChanged);
  }

  void _onDictationChanged() {
    final error = _dictation.consumeError();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictationChanged);
    _dictation.dispose();
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
    final isEmpty = ref.watch(widget.state.select((s) =>
        s.messages.isEmpty && s.streamingText == null && s.queuedMessages.isEmpty));

    ref.listen(widget.state.select((s) => s.streamingText),
        (_, __) => _scrollToBottom());
    ref.listen(widget.state.select((s) => s.messages.length),
        (_, __) => _scrollToBottom());
    ref.listen(widget.state.select((s) => s.queuedMessages.length),
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
                        final msg = messages[i];
                        // Labeled messages (e.g. the machine-built refine
                        // seed) collapse to a context chip; the full content
                        // still went to the server history.
                        if (msg.displayLabel != null) {
                          return _SeedContextChip(
                            key: ValueKey('msg-$i'),
                            label: msg.displayLabel!,
                          );
                        }
                        // Append-only list, so index keys are stable.
                        return ChatMessageBubble(
                          key: ValueKey('msg-$i'),
                          message: msg,
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
          isStreaming: isStreaming,
          hint: widget.inputHint,
          onSend: _send,
          dictation: _dictation,
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
        // Compaction runs before the model call, so its chip leads the tail.
        _CompactingChip(state: state),
        _StreamingBubble(state: state),
        _ActiveToolChips(state: state),
        _ProfileNoteChip(state: state),
        _ItineraryUpdatedChip(state: state),
        _ResultChips(state: state, notifier: notifier, onViewTrip: onViewTrip),
        if (footerBuilder != null)
          _ChatFooter(state: state, footerBuilder: footerBuilder!),
        _ErrorBanner(state: state, notifier: notifier),
        // Last: queued messages read as "up next", below the current turn and
        // any error it produced.
        _QueuedMessages(state: state, notifier: notifier),
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
      case 'check_flight_connectivity':
        return 'Checking route connectivity...';
      case 'search_events':
        return 'Finding events...';
      case 'suggest_ferries':
        return 'Finding ferries...';
      default:
        return '$tool...';
    }
  }
}

/// Transient indicator that the server is summarizing the conversation's
/// older messages before this turn (SSE `compacting`); cleared by whatever
/// event follows.
class _CompactingChip extends ConsumerWidget {
  final ProviderListenable<PlanState> state;

  const _CompactingChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compacting = ref.watch(state.select((s) => s.isCompacting));
    if (!compacting) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: Text('Summarizing earlier conversation…'),
        ),
      ),
    );
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

/// Transient acknowledgment that the current turn patched the bound trip
/// (server `trip_updated` event — only fires in refine sessions). Cleared at
/// the start of the next send, mirroring the profile-note chip lifecycle.
class _ItineraryUpdatedChip extends ConsumerWidget {
  final ProviderListenable<PlanState> state;

  const _ItineraryUpdatedChip({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updated = ref.watch(state.select((s) => s.tripUpdatedThisTurn));
    if (!updated) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          avatar: Icon(Icons.check_circle_outline,
              size: 16, color: theme.colorScheme.primary),
          label: const Text('Itinerary updated'),
        ),
      ),
    );
  }
}

/// Centered session marker rendered in place of a machine-built message (the
/// refine seed) — keeps the conversation readable without hiding that a new
/// refinement session started here.
class _SeedContextChip extends StatelessWidget {
  final String label;

  const _SeedContextChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Chip(
          avatar: Icon(Icons.auto_awesome,
              size: 14, color: theme.colorScheme.onSurfaceVariant),
          label: Text(label),
          labelStyle: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: theme.colorScheme.outlineVariant),
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
  final ProviderListenable<PlanNotifier> notifier;

  const _ErrorBanner({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(state.select((s) => s.error));
    if (error == null) return const SizedBox.shrink();
    // Narrow derived select: retry only makes sense once a user turn exists
    // for [PlanNotifier.retryLastSend] to re-run.
    final canRetry = ref.watch(state
        .select((s) => s.messages.any((m) => m.role == MessageRole.user)));
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          if (canRetry)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.onErrorContainer,
                ),
                onPressed: () => ref.read(notifier).retryLastSend(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            ),
        ],
      ),
    );
  }
}

/// User messages queued while a turn streams, rendered below the tail as
/// dimmed "up next" bubbles with a remove affordance. Kept out of the
/// committed-messages ListView so its append-only index keys stay valid.
class _QueuedMessages extends ConsumerWidget {
  final ProviderListenable<PlanState> state;
  final ProviderListenable<PlanNotifier> notifier;

  const _QueuedMessages({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Identity select works because the notifier replaces the list whole.
    final queued = ref.watch(state.select((s) => s.queuedMessages));
    if (queued.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in queued)
          _QueuedBubble(
            key: ValueKey('queued-${m.id}'),
            message: m,
            onRemove: () => ref.read(notifier).removeQueued(m.id),
          ),
      ],
    );
  }
}

class _QueuedBubble extends StatelessWidget {
  final QueuedMessage message;
  final VoidCallback onRemove;

  const _QueuedBubble({super.key, required this.message, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.45),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.displayLabel ?? message.text,
                    style: TextStyle(color: theme.colorScheme.onPrimary),
                  ),
                  Text(
                    'Queued',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove queued message',
              onPressed: onRemove,
              icon: Icon(
                Icons.close,
                size: 16,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatMessageBubble extends StatelessWidget {
  final PlanMessage message;
  final bool isStreaming;

  const ChatMessageBubble({super.key, required this.message, this.isStreaming = false});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // Agent-emitted markdown links can point at any provider, so the link
    // host stands in as the provider label.
    await trackedLaunchUrl(
      context,
      url,
      provider: uri.host.isEmpty ? 'unknown' : uri.host,
      surface: 'chat',
    );
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
                      onLinkTap: (url, title) => _openLink(context, url),
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
  final bool isStreaming;
  final String hint;
  final VoidCallback onSend;
  final DictationController dictation;

  const _InputBar({
    required this.controller,
    required this.isStreaming,
    required this.hint,
    required this.onSend,
    required this.dictation,
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
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: isStreaming ? 'Ask a follow-up…' : hint,
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
          _MicButton(dictation: dictation),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

/// The dictation mic (specs/voice-dictation). Rebuilds only itself on
/// dictation state changes; absent entirely when no capture path exists.
class _MicButton extends StatelessWidget {
  final DictationController dictation;

  const _MicButton({required this.dictation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: dictation,
      builder: (context, _) {
        if (!dictation.available) return const SizedBox.shrink();
        switch (dictation.status) {
          case DictationStatus.transcribing:
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          case DictationStatus.listening:
            return IconButton(
              tooltip: 'Stop dictating',
              onPressed: dictation.toggle,
              icon: Icon(Icons.mic, color: theme.colorScheme.error),
            );
          case DictationStatus.idle:
            return IconButton(
              tooltip: 'Dictate',
              onPressed: dictation.toggle,
              icon: const Icon(Icons.mic_none),
            );
        }
      },
    );
  }
}
