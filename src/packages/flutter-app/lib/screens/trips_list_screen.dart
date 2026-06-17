import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../navigation/app_nav.dart';
import '../theme/spacing.dart';
import '../utils/trip_format.dart';
import '../widgets/account_menu.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/status_pill.dart';
import '../models/trip.dart';
import '../providers/auth_provider.dart';
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(tripsProvider);

    Widget body;
    if (state.loading && state.trips.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (state.error != null && state.trips.isEmpty) {
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
    } else if (state.trips.isEmpty) {
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
      body = RefreshIndicator(
        onRefresh: () => ref.read(tripsProvider.notifier).loadTrips(),
        child: ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: state.trips.length,
          itemBuilder: (context, i) => _TripCard(trip: state.trips[i], isAdmin: isAdmin),
        ),
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

/// A short destination summary from the trip's hub cities: "Paris",
/// "Mexico City & Puerto Vallarta", or "Tokyo & Kyoto +2 more". Null when the
/// trip has no city data (legacy trips), so the caller falls back to the title.
String? _locationLabel(Trip t) {
  final cities = t.cities ?? const <String>[];
  if (cities.isEmpty) return null;
  if (cities.length == 1) return cities.first;
  if (cities.length == 2) return '${cities[0]} & ${cities[1]}';
  return '${cities[0]} & ${cities[1]} +${cities.length - 2} more';
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
      _locationLabel(trip) ?? trip.title,
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
        ],
      ),
    );

    if (!hasHistory) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.map_outlined),
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
