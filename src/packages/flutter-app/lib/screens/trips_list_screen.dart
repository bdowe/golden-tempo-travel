import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../navigation/app_nav.dart';
import '../theme/spacing.dart';
import '../utils/trip_format.dart';
import '../widgets/account_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/live_trip_card.dart';
import '../widgets/offline_banner.dart';
import '../widgets/status_pill.dart';
import '../models/chat_session.dart';
import '../models/plan_message.dart';
import '../models/trip.dart';
import '../providers/auth_provider.dart';
import '../providers/live_trip_provider.dart';
import '../providers/plan_provider.dart';
import '../providers/resumable_chats_provider.dart';
import '../providers/shared_with_me_provider.dart';
import '../providers/trips_provider.dart';
import 'trip_detail_screen.dart';

class TripsListScreen extends ConsumerStatefulWidget {
  const TripsListScreen({super.key});

  @override
  ConsumerState<TripsListScreen> createState() => _TripsListScreenState();
}

class _TripsListScreenState extends ConsumerState<TripsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(tripsProvider.notifier).loadTrips();
      ref.invalidate(resumableChatsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(tripsProvider);
    final resumable =
        ref.watch(resumableChatsProvider).valueOrNull ?? const <ChatSessionSummary>[];

    // A conversation that just produced a saved trip graduates out of the
    // continue section — refetch when the agent reports a saved trip.
    ref.listen(planProvider.select((s) => s.savedTripId), (prev, next) {
      if (next != null && next != prev) ref.invalidate(resumableChatsProvider);
    });

    Widget body;
    if (state.loading && state.trips.isEmpty && resumable.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && state.trips.isEmpty && resumable.isEmpty) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load trips',
        message: 'Check your connection and try again.',
        iconColor: theme.colorScheme.error.withValues(alpha: 0.6),
        actions: [
          FilledButton(
            onPressed: () => ref.read(tripsProvider.notifier).loadTrips(),
            child: const Text('Retry'),
          ),
        ],
      );
    } else if (state.trips.isEmpty && resumable.isEmpty) {
      body = EmptyState(
        icon: Icons.luggage,
        title: 'No trips yet',
        message: 'Chat with the AI agent to create your first trip.',
        actions: [
          FilledButton.icon(
            onPressed: () => ref.read(navIndexProvider.notifier).state =
                AppTab.plan.index,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Plan a trip'),
          ),
        ],
      );
    } else {
      final isAdmin = ref.watch(authProvider).user?.isAdmin ?? false;
      final shared =
          ref.watch(sharedWithMeProvider).valueOrNull ?? const <Trip>[];
      final liveTrip = ref.watch(liveTripProvider);
      body = RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(sharedWithMeProvider);
          ref.invalidate(resumableChatsProvider);
          await ref.read(tripsProvider.notifier).loadTrips();
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            // The trip happening today, promoted to the very top as a
            // one-tap shortcut (specs/happening-now). It also stays in
            // "My Trips" below — this is a spotlight, not a filter.
            if (liveTrip != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                child: LiveTripCard(
                  trip: liveTrip,
                  onTap: () => _openTrip(context, liveTrip.id),
                ),
              ),
            // In-progress AI conversations that haven't produced a trip yet
            // (specs/continue-where-you-left-off) — the discussion phase,
            // above the trips they may become.
            if (resumable.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs, 0, 0, AppSpacing.sm),
                child: Text('Continue where you left off',
                    style: theme.textTheme.titleMedium),
              ),
              for (final c in resumable) _ContinueChatCard(chat: c),
              if (state.trips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs, AppSpacing.lg, 0, AppSpacing.sm),
                  child: Text('My Trips', style: theme.textTheme.titleMedium),
                ),
            ],
            for (final t in state.trips) _TripCard(trip: t, isAdmin: isAdmin),
            // Trips others invited this user to co-plan. Kept as a separate
            // section: "mine" vs "shared with me" is the mental model, and
            // the card shows the owner instead of admin version chrome.
            if (shared.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs, AppSpacing.lg, 0, AppSpacing.sm),
                child: Text('Shared with you',
                    style: theme.textTheme.titleMedium),
              ),
              for (final t in shared) _TripCard(trip: t, isAdmin: false),
            ],
          ],
        ),
      );
    }

    // Offline: the list is a cached copy — pin the banner above it so the
    // staleness (and the way back online) is always visible.
    final offlineSince = state.offlineSince;
    if (offlineSince != null) {
      body = Column(
        children: [
          OfflineBanner(
            savedAt: offlineSince,
            onRetry: () => ref.read(tripsProvider.notifier).loadTrips(),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: const GradientAppBar(
        title: Text('My Trips'),
        actions: [AccountMenu()],
      ),
      body: body,
    );
  }
}

/// One in-progress AI conversation: tap to rehydrate it into the Plan tab,
/// dismiss (trailing ✕) to drop it from the section.
class _ContinueChatCard extends ConsumerWidget {
  final ChatSessionSummary chat;

  const _ContinueChatCard({required this.chat});

  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final detail =
          await ref.read(chatsApiServiceProvider).getChat(chat.chatId);
      ref.read(planProvider.notifier).resumeConversation(
            chatId: detail.chatId,
            summary: detail.summary,
            messages: [
              for (final m in detail.messages)
                PlanMessage(
                  role: m.role == 'user'
                      ? MessageRole.user
                      : MessageRole.assistant,
                  content: m.content,
                ),
            ],
          );
      ref.read(navIndexProvider.notifier).state = AppTab.plan.index;
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not reopen that conversation.')),
      );
    }
  }

  Future<void> _dismiss(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatsApiServiceProvider).dismissChat(chat.chatId);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not dismiss that conversation.')),
      );
    }
    ref.invalidate(resumableChatsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final updated = DateTime.tryParse(chat.updatedAt);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.forum_outlined),
        title: Text(
          chat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chat.preview.isNotEmpty)
              Text(chat.preview, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (updated != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  relativeTime(updated),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: 'Dismiss',
          onPressed: () => _dismiss(context, ref),
        ),
        onTap: () => _resume(context, ref),
      ),
    );
  }
}

void _openTrip(BuildContext context, String tripId) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TripDetailScreen(tripId: tripId)),
  );
}

/// A single trip in the list. Shows the latest version of its chat; for admins,
/// when the chat produced multiple versions it expands to list the older ones.
class _TripCard extends ConsumerWidget {
  final Trip trip;
  final bool isAdmin;

  const _TripCard({required this.trip, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versions = trip.versionCount ?? 1;
    final hasHistory = isAdmin && versions > 1 && trip.chatId != null;
    final range = tripDateRange(trip.startDate, trip.endDate);

    final title = Text(
      citiesLabel(trip.cities) ?? trip.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );

    final subtitle = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (range != null)
            _DateChip(label: range)
          else
            Text('Created ${shortDate(trip.createdAt)}'),
          StatusPill(status: trip.status),
          if (!trip.isOwner && (trip.ownerName ?? '').isNotEmpty)
            Text(
              trip.canEdit
                  ? 'Planned with ${trip.ownerName}'
                  : 'Shared by ${trip.ownerName}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );

    if (!hasHistory) {
      return Card(
        child: ListTile(
          leading: Icon(trip.isOwner
              ? Icons.map_outlined
              : trip.canEdit
                  ? Icons.group_outlined
                  : Icons.visibility_outlined),
          title: title,
          subtitle: subtitle,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openTrip(context, trip.id),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.map_outlined),
        title: title,
        subtitle: Row(
          children: [
            Expanded(child: subtitle),
            _VersionBadge(count: versions),
          ],
        ),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          _VersionList(chatId: trip.chatId!, latestId: trip.id),
        ],
      ),
    );
  }
}

/// Display-only date range, styled as a tonal pill so it pairs with the
/// [StatusPill] beside it and matches the trip-detail header's date chip.
class _DateChip extends StatelessWidget {
  final String label;
  const _DateChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionBadge extends StatelessWidget {
  final int count;
  const _VersionBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'v$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Admin-only: lazily loads and lists every version a chat produced.
class _VersionList extends ConsumerWidget {
  final String chatId;
  final String latestId;

  const _VersionList({required this.chatId, required this.latestId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Trip>>(
      future: ref.read(tripsApiServiceProvider).listTripVersions(chatId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load versions', style: theme.textTheme.bodySmall),
          );
        }
        final versions = snap.data ?? const [];
        return Column(
          children: [
            for (var i = 0; i < versions.length; i++)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 20),
                title: Text(versions[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  i == 0
                      ? 'latest · ${shortDate(versions[i].createdAt)}'
                      : 'v${versions.length - i} · ${shortDate(versions[i].createdAt)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openTrip(context, versions[i].id),
              ),
          ],
        );
      },
    );
  }
}
