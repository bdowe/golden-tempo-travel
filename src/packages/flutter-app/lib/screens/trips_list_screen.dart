import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/gradient_app_bar.dart';
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
      body = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Could not load trips', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref.read(tripsProvider.notifier).loadTrips(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (state.trips.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.luggage, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('No trips yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Chat with the AI agent to create your first trip.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final isAdmin = ref.watch(authProvider).user?.isAdmin ?? false;
      body = RefreshIndicator(
        onRefresh: () => ref.read(tripsProvider.notifier).loadTrips(),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.trips.length,
          itemBuilder: (context, i) => _TripCard(trip: state.trips[i], isAdmin: isAdmin),
        ),
      );
    }

    return Scaffold(
      appBar: const GradientAppBar(
        title: Text('My Trips'),
      ),
      body: body,
    );
  }
}

String _shortDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDt(DateTime d) => '${_mon[d.month - 1]} ${d.day}';

/// "Mon d – Mon d" from the trip's start/end (same day collapses to one);
/// null when either date is missing/unparseable.
String? _dateRange(Trip t) {
  final a = DateTime.tryParse(t.startDate ?? '');
  final b = DateTime.tryParse(t.endDate ?? '');
  if (a == null || b == null) return null;
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  return sameDay ? _fmtDt(a) : '${_fmtDt(a)} – ${_fmtDt(b)}';
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
    final range = _dateRange(trip);

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
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (range != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event, size: 14),
                const SizedBox(width: 4),
                Text(range),
              ],
            )
          else
            Text('Created ${_shortDate(trip.createdAt)}'),
          _StatusChip(status: trip.status),
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

/// Small display-only status pill: a colored dot + capitalized label.
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlanned = status == 'planned';
    final label = status.isEmpty
        ? 'Draft'
        : '${status[0].toUpperCase()}${status.substring(1)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          size: 10,
          color: isPlanned ? Colors.green : theme.colorScheme.outline,
        ),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
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
                      ? 'latest · ${_shortDate(versions[i].createdAt)}'
                      : 'v${versions.length - i} · ${_shortDate(versions[i].createdAt)}',
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
