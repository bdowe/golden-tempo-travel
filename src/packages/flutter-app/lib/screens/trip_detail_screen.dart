import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/gradient_app_bar.dart';
import '../models/trip.dart';
import '../models/trip_segment.dart';
import '../models/itinerary_item.dart';
import '../models/accommodation.dart';
import '../models/airbnb_listing.dart';
import '../providers/trips_provider.dart';
import '../providers/accommodations_provider.dart';
import '../providers/transport_provider.dart';
import '../services/accommodations_api_service.dart';
import '../services/airbnb_api_service.dart';
import '../services/transport_api_service.dart';
import '../widgets/trip_map.dart';
import 'agent_screen.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  Trip? _trip;
  bool _loading = true;
  bool _refining = false;
  String? _error;
  String _itemFilter = 'all'; // 'all' | 'attraction' | 'restaurant'
  int? _selectedPosition; // position of the place focused via a map pin / list tap

  /// Itinerary items matching the active category filter, used by both the map
  /// and the list so they stay in sync.
  List<ItineraryItem> _filtered(Trip trip) {
    final items = trip.items ?? const <ItineraryItem>[];
    return _itemFilter == 'all'
        ? items.toList()
        : items.where((i) => i.category == _itemFilter).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trip = await ref.read(tripsApiServiceProvider).getTrip(widget.tripId);
      if (mounted) setState(() => _trip = trip);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patch({String? title, String? startDate, String? endDate, String? status}) async {
    try {
      final updated = await ref.read(tripsApiServiceProvider).patchTrip(
            widget.tripId,
            title: title,
            startDate: startDate,
            endDate: endDate,
            status: status,
          );
      if (mounted) setState(() => _trip = updated);
      ref.read(tripsProvider.notifier).loadTrips(); // keep list in sync
    } catch (e) {
      _showSnack('Update failed: $e');
    }
  }

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _trip?.title ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit title'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _patch(title: result);
    }
  }

  Future<void> _editDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (range != null) {
      await _patch(startDate: _fmt(range.start), endDate: _fmt(range.end));
    }
  }

  Future<void> _refine(Trip trip) async {
    final items = trip.items ?? [];
    if (items.isEmpty) {
      _showSnack('Add some places before refining with AI.');
      return;
    }
    setState(() => _refining = true);
    try {
      final chatId = await ref.read(tripsApiServiceProvider).startRefineSession(trip.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgentScreen(chatId: chatId, initialMessage: _buildRefineSeed(trip)),
        ),
      );
    } catch (e) {
      _showSnack('Could not start refine session: $e');
    } finally {
      if (mounted) setState(() => _refining = false);
    }
  }

  /// Builds the seed message that hands the agent the trip's current itinerary,
  /// including coordinates so it can keep unchanged places without re-searching.
  String _buildRefineSeed(Trip trip) {
    final b = StringBuffer("Here's my current itinerary for \"${trip.title}\":\n");
    final items = trip.items ?? [];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final category = it.category != null ? ' [${it.category}]' : '';
      b.writeln('${i + 1}. ${it.name}$category (${it.latitude}, ${it.longitude})');
    }
    b.write("\nI'd like to refine this trip. When we're done, call create_itinerary "
        "with the full updated list of places.");
    return b.toString();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete trip?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(tripsProvider.notifier).deleteTrip(widget.tripId);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        _showSnack('Delete failed: $e');
      }
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _itemLeading(String? category, int position) {
    switch (category) {
      case 'restaurant':
        return const CircleAvatar(child: Icon(Icons.restaurant, size: 18));
      case 'attraction':
        return const CircleAvatar(child: Icon(Icons.attractions, size: 18));
      default:
        return CircleAvatar(child: Text('${position + 1}'));
    }
  }

  /// The first comma-segment of an address (e.g. "Green Turtle Cay, Abaco,
  /// Bahamas" -> "Green Turtle Cay"); null/empty addresses return null.
  String? _localityOf(String? address) {
    if (address == null) return null;
    final first = address.split(',').first.trim();
    return first.isEmpty ? null : first;
  }

  /// Groups items into consecutive runs sharing the same locality, labelling
  /// each run with the date range precomputed for that location (keyed by the
  /// first item's position).
  List<({String label, String? dateRange, List<ItineraryItem> items})> _buildGroups(
    List<ItineraryItem> items,
    Map<int, String> locationDates,
  ) {
    final groups = <({String label, String? dateRange, List<ItineraryItem> items})>[];
    String? currentKey;
    List<ItineraryItem>? current;
    for (final item in items) {
      final locality = _localityOf(item.address);
      if (current == null || locality != currentKey) {
        current = [];
        currentKey = locality;
        groups.add((
          label: locality ?? 'Other places',
          dateRange: locationDates[item.position],
          items: current,
        ));
      }
      current.add(item);
    }
    return groups;
  }

  /// Maps each itinerary item's position to its location's date range. Each
  /// location gets a contiguous slice of the trip's start–end span, weighted by
  /// how many places it has; an accommodation with its own dates overrides the
  /// computed slice. Empty when no dates can be derived. Computed over the full
  /// itinerary so the category filter doesn't shift the allocation.
  Map<int, String> _locationDates(Trip trip) {
    final items = trip.items ?? const <ItineraryItem>[];
    if (items.isEmpty) return const {};
    final stays = trip.accommodations ?? const <Accommodation>[];

    // Canonical locality runs over the full itinerary.
    final groups = <List<ItineraryItem>>[];
    String? currentKey;
    for (final item in items) {
      final locality = _localityOf(item.address);
      if (groups.isEmpty || locality != currentKey) {
        groups.add([]);
        currentKey = locality;
      }
      groups.last.add(item);
    }

    // Auto-split the trip span across groups, weighted by item count.
    final start = DateTime.tryParse(trip.startDate ?? '');
    final end = DateTime.tryParse(trip.endDate ?? '');
    final auto = List<({DateTime start, DateTime end})?>.filled(groups.length, null);
    if (start != null && end != null && !end.isBefore(start)) {
      final totalDays = end.difference(start).inDays + 1;
      final n = groups.length;
      if (n <= totalDays) {
        // Enough days: give each location a contiguous slice weighted by size.
        final counts = _allocateDays(totalDays, [for (final g in groups) g.length]);
        var cursor = start;
        for (var i = 0; i < n; i++) {
          final rStart = cursor.isAfter(end) ? end : cursor;
          var rEnd = rStart.add(Duration(days: counts[i] - 1));
          if (rEnd.isAfter(end)) rEnd = end;
          auto[i] = (start: rStart, end: rEnd);
          cursor = rEnd.add(const Duration(days: 1));
        }
      } else {
        // More locations than days: map each to a single day in order, so dates
        // stay ascending and within the trip (some days carry several stops).
        for (var i = 0; i < n; i++) {
          final d = start.add(Duration(days: (i * totalDays ~/ n).clamp(0, totalDays - 1)));
          auto[i] = (start: d, end: d);
        }
      }
    }

    final result = <int, String>{};
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final accRange = _dateRangeFor(_localityOf(g.first.address), stays);
      final a = auto[i];
      final range = accRange ?? (a == null ? null : _formatRange(a.start, a.end));
      if (range != null) {
        for (final it in g) {
          result[it.position] = range;
        }
      }
    }
    return result;
  }

  /// Splits [totalDays] across groups proportional to [weights], each group at
  /// least 1 day, summing to totalDays (largest-remainder; trims overflow from
  /// the largest groups when the min-1 floor pushes the total over).
  List<int> _allocateDays(int totalDays, List<int> weights) {
    final n = weights.length;
    if (n == 0) return const [];
    if (totalDays <= n) return List.filled(n, 1); // ranges clamp to the trip end
    final totalW = weights.fold<int>(0, (s, w) => s + (w <= 0 ? 1 : w));
    final exact = [for (final w in weights) totalDays * (w <= 0 ? 1 : w) / totalW];
    final counts = [for (final e in exact) e.floor() < 1 ? 1 : e.floor()];
    var used = counts.fold<int>(0, (s, c) => s + c);
    // Hand out any remaining days to the largest fractional remainders.
    final byRemainder = List<int>.generate(n, (i) => i)
      ..sort((a, b) => (exact[b] - exact[b].floor()).compareTo(exact[a] - exact[a].floor()));
    for (var k = 0; used < totalDays; k++) {
      counts[byRemainder[k % n]] += 1;
      used++;
    }
    // Or trim back from the largest groups if min-1 overshot.
    final byCount = List<int>.generate(n, (i) => i)..sort((a, b) => counts[b].compareTo(counts[a]));
    for (var k = 0; used > totalDays; k++) {
      final j = byCount[k % n];
      if (counts[j] > 1) {
        counts[j]--;
        used--;
      }
    }
    return counts;
  }

  String _formatRange(DateTime a, DateTime b) {
    final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
    return sameDay ? _fmtShortDt(a) : '${_fmtShortDt(a)} – ${_fmtShortDt(b)}';
  }

  String _fmtShortDt(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  /// Finds the first accommodation in [locality] with both check-in/out dates
  /// and formats them as a short range; null when nothing matches.
  String? _dateRangeFor(String? locality, List<Accommodation> stays) {
    if (locality == null) return null;
    final key = locality.toLowerCase();
    for (final acc in stays) {
      final addr = acc.address?.toLowerCase();
      if (addr == null) continue;
      if ((addr.contains(key) || key.contains(addr)) &&
          acc.checkIn != null &&
          acc.checkOut != null) {
        return '${_fmtShort(acc.checkIn!)} – ${_fmtShort(acc.checkOut!)}';
      }
    }
    return null;
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Formats a "YYYY-MM-DD" date as e.g. "Jun 10"; returns the raw string if it
  /// cannot be parsed.
  String _fmtShort(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return _fmtShortDt(d);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = _trip;

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text('Trip'),
        actions: [
          if (trip != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete trip',
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Could not load this trip'),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : trip == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(trip.title, style: theme.textTheme.headlineSmall),
                            ),
                            IconButton(icon: const Icon(Icons.edit), onPressed: _editTitle),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.event, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              (trip.startDate != null && trip.endDate != null)
                                  ? '${trip.startDate} → ${trip.endDate}'
                                  : 'No dates set',
                            ),
                            TextButton(onPressed: _editDates, child: const Text('Edit')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Status:'),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: trip.status == 'planned' ? 'planned' : 'draft',
                              items: const [
                                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                                DropdownMenuItem(value: 'planned', child: Text('Planned')),
                              ],
                              onChanged: (v) {
                                if (v != null) _patch(status: v);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _refining ? null : () => _refine(trip),
                            icon: _refining
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.auto_awesome),
                            label: Text(_refining ? 'Opening…' : 'Refine with AI'),
                          ),
                        ),
                        const Divider(height: 32),
                        if (_filtered(trip).any((i) => i.latitude != 0 || i.longitude != 0)) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              height: 240,
                              child: TripMap(
                                items: _filtered(trip),
                                selectedPosition: _selectedPosition,
                                onPinTap: (pos) {
                                  setState(() => _selectedPosition = pos);
                                  final it = trip.items!.firstWhere((i) => i.position == pos);
                                  _showSnack(it.name);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text('Itinerary', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if ((trip.items ?? []).isNotEmpty)
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final f in const [
                                ('all', 'All'),
                                ('attraction', 'Attractions'),
                                ('restaurant', 'Restaurants'),
                              ])
                                ChoiceChip(
                                  label: Text(f.$2),
                                  selected: _itemFilter == f.$1,
                                  onSelected: (_) => setState(() => _itemFilter = f.$1),
                                ),
                            ],
                          ),
                        if ((trip.items ?? []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('No places added.'),
                          )
                        else
                          Builder(builder: (_) {
                            final filtered = _filtered(trip);
                            if (filtered.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('No items match this filter.'),
                              );
                            }
                            final groups = _buildGroups(filtered, _locationDates(trip));
                            return Column(
                              children: [
                                for (final group in groups) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            group.label,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (group.dateRange != null)
                                          Row(
                                            children: [
                                              Icon(Icons.event,
                                                  size: 14, color: theme.colorScheme.primary),
                                              const SizedBox(width: 4),
                                              Text(
                                                group.dateRange!,
                                                style: theme.textTheme.labelMedium?.copyWith(
                                                    color: theme.colorScheme.primary),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                  for (final item in group.items)
                                    ListTile(
                                      leading: _itemLeading(item.category, item.position),
                                      title: Text(item.name),
                                      subtitle:
                                          item.address != null ? Text(item.address!) : null,
                                      selected: _selectedPosition == item.position,
                                      selectedTileColor:
                                          theme.colorScheme.primary.withValues(alpha: 0.08),
                                      onTap: () => setState(
                                          () => _selectedPosition = item.position),
                                    ),
                                ],
                              ],
                            );
                          }),
                        const Divider(height: 32),
                        Row(
                          children: [
                            Expanded(child: Text('Stays', style: theme.textTheme.titleMedium)),
                            TextButton.icon(
                              onPressed: () => _findStays(trip),
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('Find stays'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if ((trip.accommodations ?? []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No stays added yet.'),
                          )
                        else
                          for (final acc in trip.accommodations!)
                            ListTile(
                              leading: const Icon(Icons.hotel),
                              title: Text(acc.name),
                              subtitle: Text([
                                if (acc.provider != null) acc.provider!,
                                if (acc.checkIn != null && acc.checkOut != null)
                                  '${acc.checkIn} → ${acc.checkOut}',
                                if (acc.priceNote != null) acc.priceNote!,
                              ].join(' · ')),
                              onTap: acc.url != null ? () => _launch(acc.url!) : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteAccommodation(acc.id),
                              ),
                            ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: _addStay,
                            icon: const Icon(Icons.add),
                            label: const Text('Add a stay'),
                          ),
                        ),
                        const Divider(height: 32),
                        Text('Travel', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if ((trip.segments ?? []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No travel added yet.'),
                          )
                        else
                          for (final seg in trip.segments!)
                            ListTile(
                              leading: Icon(_segmentIcon(seg.mode)),
                              title: Text(_segmentTitle(seg)),
                              subtitle: Text(_segmentSubtitle(seg)),
                              onTap: seg.url != null ? () => _launch(seg.url!) : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteSegment(seg.id),
                              ),
                            ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _findTransport(trip, 'flight'),
                              icon: const Icon(Icons.flight, size: 18),
                              label: const Text('Find flights'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _findTransport(trip, 'ground'),
                              icon: const Icon(Icons.directions_transit, size: 18),
                              label: const Text('Find ground'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _addSegment,
                              icon: const Icon(Icons.add),
                              label: const Text('Add a segment'),
                            ),
                          ],
                        ),
                      ],
                    ),
    );
  }

  Future<void> _launch(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) _showSnack('Could not open link');
  }

  Future<void> _deleteAccommodation(String accId) async {
    try {
      await ref.read(accommodationsApiServiceProvider).delete(widget.tripId, accId);
      await _load();
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  Future<void> _findStays(Trip trip) async {
    final initial = (trip.items != null && trip.items!.isNotEmpty)
        ? trip.items!.first.name
        : trip.title;
    await showDialog<void>(
      context: context,
      builder: (_) => _FindStaysDialog(
        initialDestination: initial,
        checkIn: trip.startDate,
        checkOut: trip.endDate,
      ),
    );
  }

  Future<void> _addStay() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddStayDialog(tripId: widget.tripId),
    );
    if (added == true) await _load();
  }

  IconData _segmentIcon(String mode) {
    switch (mode) {
      case 'flight':
        return Icons.flight;
      case 'train':
        return Icons.train;
      case 'bus':
        return Icons.directions_bus;
      case 'car':
        return Icons.directions_car;
      case 'ferry':
        return Icons.directions_boat;
      default:
        return Icons.route;
    }
  }

  String _segmentTitle(TripSegment seg) {
    final parts = <String>[
      if (seg.origin != null) seg.origin!,
      if (seg.destination != null) seg.destination!,
    ];
    return parts.isEmpty ? seg.mode : parts.join(' → ');
  }

  String _segmentSubtitle(TripSegment seg) {
    return [
      seg.mode,
      if (seg.departDate != null) seg.departDate!,
      if (seg.provider != null) seg.provider!,
      if (seg.priceNote != null) seg.priceNote!,
    ].join(' · ');
  }

  Future<void> _findTransport(Trip trip, String mode) async {
    final initialDest = (trip.items != null && trip.items!.isNotEmpty)
        ? trip.items!.first.name
        : trip.title;
    await showDialog<void>(
      context: context,
      builder: (_) => _FindTransportDialog(
        mode: mode,
        initialDestination: initialDest,
        departDate: trip.startDate,
        returnDate: mode == 'flight' ? trip.endDate : null,
      ),
    );
  }

  Future<void> _addSegment() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddSegmentDialog(tripId: widget.tripId),
    );
    if (added == true) await _load();
  }

  Future<void> _deleteSegment(String segmentId) async {
    try {
      await ref.read(transportApiServiceProvider).deleteSegment(widget.tripId, segmentId);
      await _load();
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }
}

/// Lets the user browse Airbnb + Booking.com for a destination via deep links.
class _FindStaysDialog extends ConsumerStatefulWidget {
  final String initialDestination;
  final String? checkIn;
  final String? checkOut;

  const _FindStaysDialog({required this.initialDestination, this.checkIn, this.checkOut});

  @override
  ConsumerState<_FindStaysDialog> createState() => _FindStaysDialogState();
}

class _FindStaysDialogState extends ConsumerState<_FindStaysDialog> {
  late final TextEditingController _destination =
      TextEditingController(text: widget.initialDestination);
  List<ProviderLink> _links = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _getLinks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await ref.read(accommodationsApiServiceProvider).links(
            destination: _destination.text.trim(),
            checkIn: widget.checkIn,
            checkOut: widget.checkOut,
          );
      setState(() => _links = links);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _label(String provider) => provider == 'airbnb'
      ? 'Browse on Airbnb'
      : provider == 'booking'
          ? 'Browse on Booking.com'
          : provider;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find stays'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _destination,
            decoration: const InputDecoration(labelText: 'Destination'),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final link in _links)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
                  child: Text(_label(link.provider)),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: _loading ? null : _getLinks,
          child: _loading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Get links'),
        ),
      ],
    );
  }
}

/// Add a stay manually, optionally pre-filled by parsing a pasted Airbnb URL.
class _AddStayDialog extends ConsumerStatefulWidget {
  final String tripId;
  const _AddStayDialog({required this.tripId});

  @override
  ConsumerState<_AddStayDialog> createState() => _AddStayDialogState();
}

class _AddStayDialogState extends ConsumerState<_AddStayDialog> {
  final _airbnbUrl = TextEditingController();
  final _name = TextEditingController();
  final _priceNote = TextEditingController();
  String? _resolvedUrl;
  String? _provider;
  String? _address;
  double? _lat;
  double? _lng;
  bool _fetching = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _airbnbUrl.dispose();
    _name.dispose();
    _priceNote.dispose();
    super.dispose();
  }

  Future<void> _fetchAirbnb() async {
    final url = _airbnbUrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final apiClient = ref.read(accommodationsApiServiceProvider).apiClient;
      final svc = AirbnbApiService(baseUrl: apiClient.baseUrl, httpClient: apiClient.httpClient);
      final AirbnbListing listing = await svc.parseListing(url);
      setState(() {
        _name.text = listing.title;
        _resolvedUrl = listing.url.isNotEmpty ? listing.url : url;
        _provider = 'airbnb';
        _address = '${listing.location.city}, ${listing.location.country}';
        _lat = listing.location.latitude;
        _lng = listing.location.longitude;
        _priceNote.text =
            '${listing.pricing.currency} ${listing.pricing.nightlyRate.toStringAsFixed(0)}/night';
      });
    } catch (e) {
      setState(() => _error = 'Could not parse that Airbnb link');
    } finally {
      setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accommodationsApiServiceProvider).add(widget.tripId, {
        'name': _name.text.trim(),
        if (_provider != null) 'provider': _provider,
        if (_resolvedUrl != null) 'url': _resolvedUrl,
        if (_address != null) 'address': _address,
        if (_lat != null) 'latitude': _lat,
        if (_lng != null) 'longitude': _lng,
        if (_priceNote.text.trim().isNotEmpty) 'price_note': _priceNote.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a stay'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _airbnbUrl,
                    decoration: const InputDecoration(labelText: 'Airbnb link (optional)'),
                  ),
                ),
                TextButton(
                  onPressed: _fetching ? null : _fetchAirbnb,
                  child: _fetching
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Fetch'),
                ),
              ],
            ),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: _priceNote, decoration: const InputDecoration(labelText: 'Price note (optional)')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Browse Google Flights / Kayak (mode=flight) or Rome2Rio (mode=ground) via deep links.
class _FindTransportDialog extends ConsumerStatefulWidget {
  final String mode;
  final String initialDestination;
  final String? departDate;
  final String? returnDate;

  const _FindTransportDialog({
    required this.mode,
    required this.initialDestination,
    this.departDate,
    this.returnDate,
  });

  @override
  ConsumerState<_FindTransportDialog> createState() => _FindTransportDialogState();
}

class _FindTransportDialogState extends ConsumerState<_FindTransportDialog> {
  late final TextEditingController _origin = TextEditingController();
  late final TextEditingController _destination =
      TextEditingController(text: widget.initialDestination);
  List<TransportLink> _links = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _getLinks() async {
    if (_origin.text.trim().isEmpty || _destination.text.trim().isEmpty) {
      setState(() => _error = 'Origin and destination are required');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await ref.read(transportApiServiceProvider).links(
            mode: widget.mode,
            origin: _origin.text.trim(),
            destination: _destination.text.trim(),
            departDate: widget.departDate,
            returnDate: widget.returnDate,
          );
      setState(() => _links = links);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _label(String provider) {
    switch (provider) {
      case 'google_flights':
        return 'Browse on Google Flights';
      case 'kayak':
        return 'Browse on Kayak';
      case 'rome2rio':
        return 'Browse on Rome2Rio';
      default:
        return provider;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == 'flight' ? 'Find flights' : 'Find ground transport';
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _origin, decoration: const InputDecoration(labelText: 'Origin')),
            const SizedBox(height: 8),
            TextField(controller: _destination, decoration: const InputDecoration(labelText: 'Destination')),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            for (final link in _links)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
                    child: Text(_label(link.provider)),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: _loading ? null : _getLinks,
          child: _loading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Get links'),
        ),
      ],
    );
  }
}

/// Manual entry for a travel segment.
class _AddSegmentDialog extends ConsumerStatefulWidget {
  final String tripId;
  const _AddSegmentDialog({required this.tripId});

  @override
  ConsumerState<_AddSegmentDialog> createState() => _AddSegmentDialogState();
}

class _AddSegmentDialogState extends ConsumerState<_AddSegmentDialog> {
  String _mode = 'flight';
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _departDate = TextEditingController();
  final _arriveDate = TextEditingController();
  final _provider = TextEditingController();
  final _priceNote = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _departDate.dispose();
    _arriveDate.dispose();
    _provider.dispose();
    _priceNote.dispose();
    super.dispose();
  }

  String? _emptyToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(transportApiServiceProvider).addSegment(widget.tripId, {
        'mode': _mode,
        if (_emptyToNull(_origin.text) != null) 'origin': _emptyToNull(_origin.text),
        if (_emptyToNull(_destination.text) != null) 'destination': _emptyToNull(_destination.text),
        if (_emptyToNull(_departDate.text) != null) 'depart_date': _emptyToNull(_departDate.text),
        if (_emptyToNull(_arriveDate.text) != null) 'arrive_date': _emptyToNull(_arriveDate.text),
        if (_emptyToNull(_provider.text) != null) 'provider': _emptyToNull(_provider.text),
        if (_emptyToNull(_priceNote.text) != null) 'price_note': _emptyToNull(_priceNote.text),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a segment'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(value: 'flight', child: Text('Flight')),
                DropdownMenuItem(value: 'train', child: Text('Train')),
                DropdownMenuItem(value: 'bus', child: Text('Bus')),
                DropdownMenuItem(value: 'car', child: Text('Car')),
                DropdownMenuItem(value: 'ferry', child: Text('Ferry')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _mode = v ?? 'flight'),
            ),
            TextField(controller: _origin, decoration: const InputDecoration(labelText: 'Origin')),
            TextField(controller: _destination, decoration: const InputDecoration(labelText: 'Destination')),
            TextField(controller: _departDate, decoration: const InputDecoration(labelText: 'Depart date (YYYY-MM-DD)')),
            TextField(controller: _arriveDate, decoration: const InputDecoration(labelText: 'Arrive date (YYYY-MM-DD)')),
            TextField(controller: _provider, decoration: const InputDecoration(labelText: 'Provider / Airline (optional)')),
            TextField(controller: _priceNote, decoration: const InputDecoration(labelText: 'Price note (optional)')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
