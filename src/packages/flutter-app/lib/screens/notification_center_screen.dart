import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
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
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notifTitle)),
      body: PageContainer(
        child: notifs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(
            icon: Icons.cloud_off,
            title: l10n.notifLoadErrorTitle,
            message: '$e'.replaceFirst('Exception: ', ''),
            actions: [
              FilledButton(
                onPressed: () => ref.invalidate(notificationsProvider),
                child: Text(l10n.commonRetry),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.notifications_none,
                title: l10n.notifEmptyTitle,
                message: l10n.notifEmptyMessage,
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
    final when = relativeTime(
        context.l10n, DateTime.parse(notification.createdAt).toLocal());

    final content = switch (notification.type) {
      'price_drop' =>
        _PriceDropBody(payload: notification.payload, unread: unread),
      'collab_edit' || 'invite_accepted' => _TripSignalBody(
          type: notification.type,
          payload: notification.payload,
          unread: unread,
        ),
      _ => _GenericBody(
          type: notification.type,
          payload: notification.payload,
          unread: unread,
        ),
    };

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

  String _dropLine(AppLocalizations l10n) {
    final price = _num('price') ?? 0;
    final currency = _str('currency') ?? '';
    final now = formatMoney(price, currency);
    final prev = _num('previous_price');
    if (prev != null) {
      return l10n.notifDownFrom(now, formatMoney(prev, currency));
    }
    return now;
  }

  String _datesLine(AppLocalizations l10n) {
    final depart = _str('depart_date') ?? '';
    final matched = _str('matched_date');
    var s = matched ?? depart;
    final ret = _str('return_date');
    if (ret != null) s += ' → $ret';
    if (matched != null && matched != depart) {
      s += ' ${l10n.notifBestInWindow}';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
          _dropLine(l10n),
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            color: unread
                ? Colors.green.shade800
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _datesLine(l10n),
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

  static String _humanize(String type, AppLocalizations l10n) {
    if (type.isEmpty) return l10n.notifGenericFallback;
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
            : _humanize(type, context.l10n);
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

/// Trip collaboration signals: a co-planner edited a shared trip
/// (`collab_edit`) or someone accepted an invite (`invite_accepted`). Both read
/// as "<who> <did what> <trip>" with a leading icon, built from the payload's
/// actor/trip fields.
class _TripSignalBody extends StatelessWidget {
  final String type;
  final Map<String, dynamic> payload;
  final bool unread;
  const _TripSignalBody({
    required this.type,
    required this.payload,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tripTitle = payload['trip_title'] is String
        ? payload['trip_title'] as String
        : l10n.notifSomeTrip;
    final IconData icon;
    final String headline;
    if (type == 'invite_accepted') {
      final who = payload['accepter_name'] is String
          ? payload['accepter_name'] as String
          : l10n.notifSomeone;
      icon = Icons.group_add_outlined;
      headline = l10n.notifJoinedTrip(who, tripTitle);
    } else {
      final who = payload['actor_name'] is String
          ? payload['actor_name'] as String
          : l10n.notifACollaborator;
      icon = Icons.edit_outlined;
      headline = l10n.notifEditedTrip(who, tripTitle);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
          child: Icon(
            icon,
            size: 18,
            color: unread
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
              color: unread
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
