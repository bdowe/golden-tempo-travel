import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../providers/notifications_provider.dart';
import '../theme/spacing.dart';
import '../utils/money_format.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart' show relativeTime;
import '../widgets/page_container.dart';

/// The notification center (Wave 16): every notification as a durable,
/// read/unread feed row. Type-agnostic — each row renders from its `type` +
/// `payload`, so price drops, trip reminders and future types share one center.
/// Opening the center is the read action — mark-all-read fires on open, then
/// the badge clears.
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
    // Opening the center marks all notifications read (mark-all is the read
    // model), then refreshes both the feed (so rows show as read) and the badge.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  Future<void> _markRead() async {
    try {
      await ref.read(notificationsApiServiceProvider).markRead();
    } catch (_) {
      // Best-effort: a failed mark-read shouldn't block reading the feed. The
      // badge simply stays until the next successful open.
    }
    if (!mounted) return;
    ref.invalidate(notificationsUnreadCountProvider);
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final notifs = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: PageContainer(
        child: notifs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not load notifications',
            message: '$e'.replaceFirst('Exception: ', ''),
            actions: [
              FilledButton(
                onPressed: () => ref.invalidate(notificationsProvider),
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
              onRefresh: () async => ref.invalidate(notificationsProvider),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _NotificationTile(notification: list[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One feed row. The chrome (unread dot + timestamp + card) is shared; the body
/// is chosen by `type`: `price_drop` renders the flight-specific layout from its
/// payload, and any unrecognized type falls back to a generic title/subtitle so
/// a new backend type is never a blank row.
class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = notification.isUnread;
    final when =
        relativeTime(DateTime.parse(notification.createdAt).toLocal());

    final content = notification.type == 'price_drop'
        ? _PriceDropBody(payload: notification.payload, unread: unread)
        : _GenericBody(
            type: notification.type,
            payload: notification.payload,
            unread: unread,
          );

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
                  content,
                  const SizedBox(height: 2),
                  Text(
                    when,
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

/// The price-drop layout: route, the drop ("$412, down from $498") and the
/// (possibly flexible) dates — built entirely from the payload map.
class _PriceDropBody extends StatelessWidget {
  final Map<String, dynamic> payload;
  final bool unread;
  const _PriceDropBody({required this.payload, required this.unread});

  String? _str(String k) {
    final v = payload[k];
    return v is String ? v : null;
  }

  double? _num(String k) {
    final v = payload[k];
    return v is num ? v.toDouble() : null;
  }

  String _dropLine() {
    final price = _num('price') ?? 0;
    final currency = _str('currency') ?? '';
    final now = formatMoney(price, currency);
    final prev = _num('previous_price');
    if (prev != null) {
      return '$now, down from ${formatMoney(prev, currency)}';
    }
    return now;
  }

  String _datesLine() {
    final depart = _str('depart_date') ?? '';
    final matched = _str('matched_date');
    var s = matched ?? depart;
    final ret = _str('return_date');
    if (ret != null) s += ' → $ret';
    if (matched != null && matched != depart) s += ' (best in window)';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = _str('origin') ?? '';
    final destination = _str('destination') ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$origin → $destination',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
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
            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            color: unread
                ? Colors.green.shade800
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _datesLine(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Fallback layout for any type the client doesn't specialize yet. Reads a
/// `title` (or `message`/`body`) from the payload, else humanizes the type
/// name, so a newly-added backend notification always renders something
/// sensible instead of a blank row.
class _GenericBody extends StatelessWidget {
  final String type;
  final Map<String, dynamic> payload;
  final bool unread;
  const _GenericBody({
    required this.type,
    required this.payload,
    required this.unread,
  });

  static String _humanize(String type) {
    if (type.isEmpty) return 'Notification';
    return type
        .split(RegExp(r'[_\s]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title =
        (payload['title'] is String && (payload['title'] as String).isNotEmpty)
            ? payload['title'] as String
            : _humanize(type);
    final subtitle = payload['message'] is String
        ? payload['message'] as String
        : payload['body'] is String
            ? payload['body'] as String
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
            color: unread
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
