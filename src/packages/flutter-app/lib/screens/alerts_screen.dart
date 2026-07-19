import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/price_alert.dart';
import '../providers/alerts_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/spacing.dart';
import '../utils/money_format.dart';
import '../widgets/empty_state.dart';
import '../widgets/offline_banner.dart' show relativeTime;
import '../widgets/page_container.dart';
import '../widgets/status_pill.dart';
import 'auth_screen.dart';
import 'notification_center_screen.dart';
import '../utils/snack.dart';

/// The traveler's watched routes (specs/price-alerts): state at a glance,
/// pause/resume/delete. Creation happens from flight search results.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authProvider).isSignedIn) {
        ref.read(alertsProvider.notifier).load();
      }
    });
  }

  /// Routes through sign-in, then loads alerts once a session exists — the
  /// /alerts email deep link lands here signed-out on a fresh device, and a
  /// prompt without an action is a dead end (same pattern as
  /// shared_trip_screen's _ensureSignedIn).
  Future<void> _signIn() async {
    if (!ref.read(authProvider).isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
    if (!mounted || !ref.read(authProvider).isSignedIn) return;
    // The isSignedIn listener in build usually kicks off the load the moment
    // the session lands; only load here if it hasn't already.
    final alerts = ref.read(alertsProvider);
    if (!alerts.loaded && !alerts.loading) {
      ref.read(alertsProvider.notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // The /alerts email deep link routes here directly, often before the
    // async session restore finishes — reload once sign-in state arrives.
    ref.listen(authProvider.select((s) => s.isSignedIn), (prev, signedIn) {
      if (signedIn && !ref.read(alertsProvider).loaded) {
        ref.read(alertsProvider.notifier).load();
      }
    });
    final auth = ref.watch(authProvider);
    final state = ref.watch(alertsProvider);

    Widget body;
    if (!auth.isSignedIn) {
      body = EmptyState(
        icon: Icons.notifications_none,
        title: 'Sign in to watch fares',
        message: 'Price alerts email you when a flight you care about drops.',
        actions: [
          FilledButton(
            onPressed: _signIn,
            child: const Text('Sign in'),
          ),
        ],
      );
    } else if (state.loading && !state.loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && state.alerts.isEmpty) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load alerts',
        message: state.error,
        actions: [
          FilledButton(
            onPressed: () => ref.read(alertsProvider.notifier).load(),
            child: const Text('Retry'),
          ),
        ],
      );
    } else if (state.alerts.isEmpty) {
      body = const EmptyState(
        icon: Icons.notifications_none,
        title: 'No alerts yet',
        message:
            'Search a flight and tap "Watch this route" — we\'ll email you '
            'when the price drops.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => ref.read(alertsProvider.notifier).load(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: state.alerts.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) => _AlertCard(alert: state.alerts[i]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Price alerts'),
        actions: [if (auth.isSignedIn) const _NotificationBell()],
      ),
      body: PageContainer(child: body),
    );
  }
}

/// Bell with an unread badge that opens the notification center
/// (specs/price-alerts-v2). The badge is the "something happened" pull; opening
/// the center marks all read and clears it.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(alertUnreadCountProvider).valueOrNull ?? 0;
    final bell = IconButton(
      tooltip: 'Notifications',
      icon: const Icon(Icons.notifications_none),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationCenterScreen()),
      ),
    );
    if (count == 0) return bell;
    return Badge.count(count: count, child: bell);
  }
}

class _AlertCard extends ConsumerWidget {
  final PriceAlert alert;
  const _AlertCard({required this.alert});

  String _priceLine() {
    final cur = alert.currency ?? '';
    final checked = alert.lastCheckedPrice;
    final parts = <String>[];
    if (checked != null) {
      parts.add('Last seen ${formatMoney(checked, cur)}');
    }
    if (alert.targetPrice != null) {
      parts.add('target ${formatMoney(alert.targetPrice!, cur)}');
    } else {
      parts.add('watching for any drop');
    }
    return parts.join(' · ');
  }

  String _datesLine() {
    var s = alert.departDate;
    if (alert.returnDate != null) s += ' → ${alert.returnDate}';
    if (alert.flexDays > 0) s += ' · ±${alert.flexDays}d';
    if (alert.adults > 1) s += ' · ${alert.adults} adults';
    if (alert.cabinClass != 'economy') {
      s += ' · ${alert.cabinClass.replaceAll('_', ' ')}';
    }
    return s;
  }

  /// "down $X from when you started watching" — only when the latest check is
  /// below the baseline the watch started from (both present).
  String? _baselineDeltaLine() {
    final base = alert.baselinePrice;
    final checked = alert.lastCheckedPrice;
    if (base == null || checked == null || checked >= base) return null;
    final cur = alert.currency ?? '';
    return 'Down ${formatMoney(base - checked, cur)} from when you started watching';
  }

  /// "Checked 2 hours ago" from the last check time, if we have one.
  String? _freshnessLine() {
    final at = alert.lastCheckedAt;
    if (at == null) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return 'Checked ${relativeTime(parsed.toLocal())}';
  }

  Future<void> _editTarget(BuildContext context, WidgetRef ref) async {
    final cur = alert.currency ?? '';
    final controller = TextEditingController(
      text: alert.targetPrice?.toStringAsFixed(0) ?? '',
    );
    final hasTarget = alert.targetPrice != null;
    final result = await showDialog<({double? target, bool clear})>(
      context: context,
      builder: (dialogCtx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Set target price'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Get notified when the fare hits or drops below this price.',
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Notify me at or below',
                    prefixText: cur.isEmpty ? null : '$cur ',
                    border: const OutlineInputBorder(),
                    errorText: error,
                  ),
                ),
                // Only a target-mode alert can be reverted; an any-drop alert
                // is already there.
                if (hasTarget) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => Navigator.of(dialogCtx)
                        .pop((target: null, clear: true)),
                    child: const Text('Watch for any drop instead'),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(controller.text.trim());
                  if (v == null || v <= 0) {
                    setState(() => error = 'Enter a valid target price');
                    return;
                  }
                  Navigator.of(dialogCtx).pop((target: v, clear: false));
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || !context.mounted) return;
    try {
      final notifier = ref.read(alertsProvider.notifier);
      if (result.clear) {
        await notifier.clearTarget(alert.id);
      } else {
        await notifier.updateTarget(alert.id, result.target!);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(alertsProvider.notifier);
    final paused = alert.status == 'paused';
    final expired = alert.status == 'expired';
    final baselineDelta = _baselineDeltaLine();
    final freshness = _freshnessLine();

    Future<void> guard(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showSnack(context, '$e');
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${alert.origin} → ${alert.destination}',
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _AlertPill(alert: alert),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(_datesLine(), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 2),
                  Text(
                    _priceLine(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (baselineDelta != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      baselineDelta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (freshness != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      freshness,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Alert actions',
              onSelected: (v) {
                if (v == 'edit_target') _editTarget(context, ref);
                if (v == 'pause') guard(() => notifier.setPaused(alert.id, true));
                if (v == 'resume') {
                  guard(() => notifier.setPaused(alert.id, false));
                }
                if (v == 'delete') guard(() => notifier.remove(alert.id));
              },
              itemBuilder: (_) => [
                if (!expired)
                  PopupMenuItem(
                    value: 'edit_target',
                    child: Text(alert.targetPrice == null
                        ? 'Set target price'
                        : 'Edit target price'),
                  ),
                if (!expired)
                  PopupMenuItem(
                    value: paused ? 'resume' : 'pause',
                    child: Text(paused ? 'Resume' : 'Pause'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small tonal pill carrying the alert's state. "Price dropped" (green) wins
/// over the raw status because it is the state the traveler cares about.
class _AlertPill extends StatelessWidget {
  final PriceAlert alert;
  const _AlertPill({required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String label;
    final Color bg;
    final Color fg;
    if (alert.status == 'expired') {
      label = 'Expired';
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else if (alert.status == 'paused') {
      label = 'Paused';
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurfaceVariant;
    } else if (alert.hasTriggered) {
      label = 'Price dropped';
      bg = Colors.green.withValues(alpha: 0.15);
      fg = Colors.green.shade800;
    } else {
      label = 'Watching';
      bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.5);
      fg = theme.colorScheme.onPrimaryContainer;
    }
    return StatusPill.custom(label: label, background: bg, foreground: fg);
  }
}
