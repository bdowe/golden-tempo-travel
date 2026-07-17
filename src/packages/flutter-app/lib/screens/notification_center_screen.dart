import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert_event.dart';
import '../providers/alerts_provider.dart';
import '../theme/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart' show relativeTime;
import '../widgets/page_container.dart';

/// The notification center (specs/price-alerts-v2): every price drop as a
/// durable, read/unread feed row. Opening the center is the read action —
/// mark-all-read fires on open, then the badge clears.
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the center marks all events read (mark-all is the read model),
    // then refreshes both the feed (so rows show as read) and the badge.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    try {
      await ref.read(alertsApiServiceProvider).markAlertEventsRead();
    } catch (_) {
      // Best-effort: a failed mark-read shouldn't block reading the feed. The
      // badge simply stays until the next successful open.
    }
    if (!mounted) return;
    ref.invalidate(alertUnreadCountProvider);
    ref.invalidate(alertEventsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(alertEventsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: PageContainer(
        child: events.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not load notifications',
            message: '$e'.replaceFirst('Exception: ', ''),
            actions: [
              FilledButton(
                onPressed: () => ref.invalidate(alertEventsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.notifications_none,
                title: 'No notifications yet',
                message:
                    'Price drops on routes you watch will show up here.',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(alertEventsProvider),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _EventTile(event: list[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One drop in the feed: route, the drop ("$412, down from $498"), and how long
/// ago. Unread rows get an accent dot and bolder text; read rows are muted.
class _EventTile extends StatelessWidget {
  final AlertEvent event;
  const _EventTile({required this.event});

  String _dropLine() {
    final cur = event.currency.isEmpty ? '' : '${event.currency} ';
    final now = '$cur${event.price.toStringAsFixed(0)}';
    if (event.previousPrice != null) {
      return '$now, down from $cur${event.previousPrice!.toStringAsFixed(0)}';
    }
    return now;
  }

  String _datesLine() {
    // A flexible alert reports the cheapest day it found; show that instead of
    // the nominal departure so the traveler books the right date.
    var s = event.matchedDate ?? event.departDate;
    if (event.returnDate != null) s += ' → ${event.returnDate}';
    if (event.matchedDate != null && event.matchedDate != event.departDate) {
      s += ' (best in window)';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = event.isUnread;
    final when = relativeTime(DateTime.parse(event.occurredAt).toLocal());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Unread accent dot; a spacer keeps read rows aligned.
            Padding(
              padding: const EdgeInsets.only(top: 6, right: AppSpacing.md),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: unread
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event.origin} → ${event.destination}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight:
                          unread ? FontWeight.w700 : FontWeight.w500,
                      color: unread
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dropLine(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          unread ? FontWeight.w600 : FontWeight.w400,
                      color: unread
                          ? Colors.green.shade800
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_datesLine()} · $when',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
