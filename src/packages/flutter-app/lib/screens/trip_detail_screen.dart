import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/gradient_app_bar.dart';
import '../models/trip.dart';
import '../models/itinerary_item.dart';
import '../models/accommodation.dart';
import '../models/booking_todo.dart';
import '../providers/trips_provider.dart';
import '../providers/booking_todos_provider.dart';
import '../widgets/booking_todo_card.dart';
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
  List<BookingTodo> _bookingTodos = [];
  bool _overviewExpanded = false;

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
      if (mounted) {
        setState(() {
          _trip = trip;
          _bookingTodos = trip.bookingTodos ?? [];
        });
      }
      if (mounted && (trip.items ?? const []).isNotEmpty) {
        await _syncBookingTodos(trip);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Pushes the itinerary-derived booking checklist to the server, which upserts
  /// auto-TODOs (preserving booked state) and prunes legs no longer in the trip.
  Future<void> _syncBookingTodos(Trip trip) async {
    try {
      final todos = await ref
          .read(bookingTodosApiServiceProvider)
          .syncTodos(trip.id, _deriveTodos(trip));
      if (mounted) setState(() => _bookingTodos = todos);
    } catch (_) {
      // Non-fatal: keep whatever booking todos came with the trip.
    }
  }

  /// Builds the auto-TODO payload from the itinerary's location groups: a stay
  /// per city (with its dates) and a transport leg between consecutive cities.
  List<Map<String, dynamic>> _deriveTodos(Trip trip) {
    final ranges = _locationGroupRanges(trip);
    final todos = <Map<String, dynamic>>[];
    var pos = 0;
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      final label = r.label;
      final checkIn = r.start == null ? null : _fmt(r.start!);
      final checkOut = r.end == null ? null : _fmt(r.end!);
      todos.add({
        'kind': 'stay',
        'todo_key': 'stay:${label.toLowerCase()}',
        'title': 'Stay in $label',
        if (r.start != null && r.end != null)
          'subtitle': _formatRange(r.start!, r.end!),
        'provider': 'airbnb',
        'position': pos++,
        'destination': label,
        if (checkIn != null) 'depart_date': checkIn,
        if (checkOut != null) 'return_date': checkOut,
        'guests': 1,
      });
      if (i < ranges.length - 1) {
        final next = ranges[i + 1];
        final depart = r.end == null ? null : _fmt(r.end!);
        todos.add({
          'kind': 'transport',
          'todo_key':
              'transport:${label.toLowerCase()}>>${next.label.toLowerCase()}',
          'title': '$label → ${next.label}',
          if (r.end != null) 'subtitle': _fmtShortDt(r.end!),
          'provider': 'google_flights',
          'position': pos++,
          'origin': label,
          'destination': next.label,
          if (depart != null) 'depart_date': depart,
          'passengers': 1,
        });
      }
    }
    return todos;
  }

  Future<void> _setBooked(BookingTodo todo, bool booked) async {
    final prev = _bookingTodos;
    setState(() {
      _bookingTodos = [
        for (final t in _bookingTodos)
          if (t.id == todo.id) t.copyWith(booked: booked) else t,
      ];
    });
    try {
      await ref
          .read(bookingTodosApiServiceProvider)
          .setBooked(widget.tripId, todo.id, booked);
    } catch (e) {
      if (mounted) setState(() => _bookingTodos = prev);
      _showSnack('Update failed: $e');
    }
  }

  Future<void> _deleteTodo(BookingTodo todo) async {
    try {
      await ref.read(bookingTodosApiServiceProvider).delete(widget.tripId, todo.id);
      if (mounted) {
        setState(() =>
            _bookingTodos = _bookingTodos.where((t) => t.id != todo.id).toList());
      }
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  Future<void> _addBooking() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddBookingTodoDialog(tripId: widget.tripId),
    );
    if (added == true) await _load();
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

  /// A stored title is "long" when it's really the AI summary (multi-line or
  /// lengthy); such trips get a computed display title instead.
  bool _titleIsLong(String t) => t.contains('\n') || t.length > 60;

  /// What to show as the header title: the trip's own title when it's concise,
  /// otherwise a title computed from the itinerary's cities + dates.
  String _displayTitle(Trip t) =>
      _titleIsLong(t.title) ? _computedTitle(t) : t.title;

  /// The overview prose: the dedicated summary when present, else the long
  /// stored title (legacy trips), else nothing.
  String? _overviewText(Trip t) =>
      t.summary ?? (_titleIsLong(t.title) ? t.title : null);

  /// Builds "City" / "City & City" / "City & City +N more", with the trip's date
  /// range appended when available. Falls back to the (truncated) stored title.
  String _computedTitle(Trip t) {
    final cities = <String>[];
    for (final it in t.items ?? const <ItineraryItem>[]) {
      final c = _hubOf(it);
      if (c != null && c.isNotEmpty && !cities.contains(c)) cities.add(c);
    }
    String label;
    if (cities.isEmpty) {
      final firstLine = t.title.split('\n').first.trim();
      label = firstLine.length > 40
          ? '${firstLine.substring(0, 40).trim()}…'
          : (firstLine.isEmpty ? 'Trip' : firstLine);
    } else if (cities.length <= 2) {
      label = cities.join(' & ');
    } else {
      label = '${cities.take(2).join(' & ')} +${cities.length - 2} more';
    }
    final start = DateTime.tryParse(t.startDate ?? '');
    final end = DateTime.tryParse(t.endDate ?? '');
    if (start != null && end != null && !end.isBefore(start)) {
      return '$label · ${_formatRange(start, end)}';
    }
    return label;
  }

  /// The group an item belongs to: its day-trip hub city when set, else its own
  /// city. Day trips (e.g. Versailles) thus fold under the hub (e.g. Paris).
  String? _hubOf(ItineraryItem item) {
    final h = item.dayTripFrom?.trim();
    if (h != null && h.isNotEmpty) return h;
    return _cityOf(item);
  }

  /// The city an item belongs to: the AI-assigned [ItineraryItem.city] when set,
  /// otherwise a best-effort parse of the formatted address.
  String? _cityOf(ItineraryItem item) {
    final c = item.city?.trim();
    if (c != null && c.isNotEmpty) return c;
    return _cityFromAddress(item.address);
  }

  /// Fallback city from a formatted address. Drops the country (last segment)
  /// and strips postal-code tokens from the segment before it, e.g.
  /// "Av. ..., 1400-206 Lisboa, Portugal" -> "Lisboa"; a bare "Paris" stays as is.
  String? _cityFromAddress(String? address) {
    if (address == null) return null;
    final parts =
        address.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first;
    final candidate = parts[parts.length - 2]; // segment before the country
    final tokens = candidate
        .split(RegExp(r'\s+'))
        .where((t) => !RegExp(r'^[0-9][0-9\-]*$').hasMatch(t)) // drop postal tokens
        .toList();
    final city = tokens.join(' ').trim();
    return city.isEmpty ? candidate : city;
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
      final locality = _hubOf(item);
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

  /// Renders a hub group's items, batching consecutive day-trip places (by town)
  /// under an indented "Day trip · <town>" sub-header so nearby towns read as
  /// excursions from the hub city rather than separate stops.
  List<Widget> _buildGroupItemWidgets(List<ItineraryItem> items, ThemeData theme) {
    final widgets = <Widget>[];
    var i = 0;
    while (i < items.length) {
      final dt = items[i].dayTripFrom?.trim();
      if (dt != null && dt.isNotEmpty) {
        final town = _cityOf(items[i]) ?? 'Day trip';
        widgets.add(_dayTripSubHeader(town, theme));
        while (i < items.length) {
          final it = items[i];
          final d = it.dayTripFrom?.trim();
          if (d != null && d.isNotEmpty && _cityOf(it) == town) {
            widgets.add(_itemTile(it, 32, theme));
            i++;
          } else {
            break;
          }
        }
      } else {
        widgets.add(_itemTile(items[i], 12, theme));
        i++;
      }
    }
    return widgets;
  }

  Widget _dayTripSubHeader(String town, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
        child: Row(
          children: [
            Icon(Icons.directions_bus, size: 16, color: theme.colorScheme.secondary),
            const SizedBox(width: 6),
            Text(
              'Day trip · $town',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _itemTile(ItineraryItem item, double indentLeft, ThemeData theme) => Padding(
        padding: EdgeInsets.only(left: indentLeft),
        child: ListTile(
          leading: _itemLeading(item.category, item.position),
          title: Text(item.name),
          subtitle: item.address != null ? Text(item.address!) : null,
          trailing: item.timeOfDay == null
              ? null
              : _TimeOfDayChip(timeOfDay: item.timeOfDay!),
          selected: _selectedPosition == item.position,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          onTap: () => setState(() => _selectedPosition = item.position),
        ),
      );

  /// Maps each itinerary item's position to its location's formatted date range.
  /// Delegates to [_locationGroupRanges] so the itinerary labels and the booking
  /// checklist derive dates the same way.
  Map<int, String> _locationDates(Trip trip) {
    final items = trip.items ?? const <ItineraryItem>[];
    if (items.isEmpty) return const {};
    final ranges = _locationGroupRanges(trip);
    final result = <int, String>{};
    var gi = -1;
    String? currentKey;
    for (final item in items) {
      final locality = _hubOf(item);
      if (gi < 0 || locality != currentKey) {
        gi++;
        currentKey = locality;
      }
      final r = ranges[gi];
      if (r.start != null && r.end != null) {
        result[item.position] = _formatRange(r.start!, r.end!);
      }
    }
    return result;
  }

  /// Per-location-group label and date range. Each location gets a contiguous
  /// slice of the trip's start–end span, weighted by how many places it has; an
  /// accommodation with its own dates overrides the computed slice. Computed over
  /// the full itinerary so the category filter doesn't shift the allocation.
  List<({String label, DateTime? start, DateTime? end})> _locationGroupRanges(Trip trip) {
    final items = trip.items ?? const <ItineraryItem>[];
    if (items.isEmpty) return const [];
    final stays = trip.accommodations ?? const <Accommodation>[];

    // Canonical locality runs over the full itinerary.
    final groups = <List<ItineraryItem>>[];
    String? currentKey;
    for (final item in items) {
      final locality = _hubOf(item);
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

    final result = <({String label, DateTime? start, DateTime? end})>[];
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final locality = _hubOf(g.first);
      final accRange = _accDateRangeFor(locality, stays);
      final a = auto[i];
      result.add((
        label: locality ?? 'Other places',
        start: accRange?.start ?? a?.start,
        end: accRange?.end ?? a?.end,
      ));
    }
    return result;
  }

  /// First accommodation in [locality] with both check-in/out dates, as DateTimes.
  ({DateTime start, DateTime end})? _accDateRangeFor(
      String? locality, List<Accommodation> stays) {
    if (locality == null) return null;
    final key = locality.toLowerCase();
    for (final acc in stays) {
      final addr = acc.address?.toLowerCase();
      if (addr == null) continue;
      if ((addr.contains(key) || key.contains(addr)) &&
          acc.checkIn != null &&
          acc.checkOut != null) {
        final ci = DateTime.tryParse(acc.checkIn!);
        final co = DateTime.tryParse(acc.checkOut!);
        if (ci != null && co != null) return (start: ci, end: co);
      }
    }
    return null;
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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// The trip's hero header: title (+ rename), date/status chips, a Refine
  /// button, and a collapsible overview.
  Widget _buildHeaderCard(Trip trip, ThemeData theme) {
    final overview = _overviewText(trip);
    final hasDates = trip.startDate != null && trip.endDate != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _displayTitle(trip),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'Rename',
                  onPressed: _editTitle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.event, size: 16),
                  label: Text(hasDates
                      ? '${trip.startDate} → ${trip.endDate}'
                      : 'Add dates'),
                  onPressed: _editDates,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _patch(status: v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'draft', child: Text('Draft')),
                    PopupMenuItem(value: 'planned', child: Text('Planned')),
                  ],
                  child: Chip(
                    avatar: Icon(
                      Icons.circle,
                      size: 12,
                      color: trip.status == 'planned'
                          ? Colors.green
                          : theme.colorScheme.outline,
                    ),
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(trip.status == 'planned' ? 'Planned' : 'Draft'),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
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
            if (overview != null) ...[
              const SizedBox(height: 16),
              Text(
                'Overview',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                overview,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: _overviewExpanded ? null : 3,
                overflow: _overviewExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
              if (overview.length > 140)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        setState(() => _overviewExpanded = !_overviewExpanded),
                    child: Text(_overviewExpanded ? 'Show less' : 'Show more'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
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
                        _buildHeaderCard(trip, theme),
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
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.location_on,
                                                size: 18, color: theme.colorScheme.primary),
                                            const SizedBox(width: 6),
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
                                                      size: 14,
                                                      color: theme.colorScheme.primary),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    group.dateRange!,
                                                    style: theme.textTheme.labelMedium
                                                        ?.copyWith(
                                                            color:
                                                                theme.colorScheme.primary),
                                                  ),
                                                ],
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        const Divider(height: 1),
                                      ],
                                    ),
                                  ),
                                  ..._buildGroupItemWidgets(group.items, theme),
                                ],
                              ],
                            );
                          }),
                        const Divider(height: 32),
                        Row(
                          children: [
                            Expanded(child: Text('Bookings', style: theme.textTheme.titleMedium)),
                            TextButton.icon(
                              onPressed: _addBooking,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_bookingTodos.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                                'No bookings yet — they appear here once your itinerary has places.'),
                          )
                        else
                          for (final todo in _bookingTodos)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: BookingTodoCard(
                                todo: todo,
                                onBookedChanged: (v) => _setBooked(todo, v),
                                onOpen: todo.searchUrl != null
                                    ? () => _launch(todo.searchUrl!)
                                    : null,
                                onDelete:
                                    todo.auto ? null : () => _deleteTodo(todo),
                              ),
                            ),
                      ],
                    ),
    );
  }

  Future<void> _launch(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) _showSnack('Could not open link');
  }

}

/// Adds a custom booking TODO. A destination (and optional dates) lets the
/// server build the search link; a pasted link overrides it.
class _AddBookingTodoDialog extends ConsumerStatefulWidget {
  final String tripId;
  const _AddBookingTodoDialog({required this.tripId});

  @override
  ConsumerState<_AddBookingTodoDialog> createState() =>
      _AddBookingTodoDialogState();
}

class _AddBookingTodoDialogState extends ConsumerState<_AddBookingTodoDialog> {
  String _kind = 'stay';
  final _title = TextEditingController();
  final _destination = TextEditingController();
  final _origin = TextEditingController();
  final _departDate = TextEditingController();
  final _returnDate = TextEditingController();
  final _url = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _destination.dispose();
    _origin.dispose();
    _departDate.dispose();
    _returnDate.dispose();
    _url.dispose();
    super.dispose();
  }

  String? _nn(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final isTransport = _kind == 'transport';
      await ref.read(bookingTodosApiServiceProvider).addTodo(widget.tripId, {
        'kind': _kind,
        'title': _title.text.trim(),
        if (_nn(_destination.text) != null) 'destination': _nn(_destination.text),
        if (isTransport && _nn(_origin.text) != null) 'origin': _nn(_origin.text),
        if (_nn(_departDate.text) != null) 'depart_date': _nn(_departDate.text),
        if (!isTransport && _nn(_returnDate.text) != null)
          'return_date': _nn(_returnDate.text),
        if (_nn(_url.text) != null) 'search_url': _nn(_url.text),
        if (_kind == 'stay') 'provider': 'airbnb',
        if (isTransport) 'provider': 'google_flights',
        'guests': 1,
        'passengers': 1,
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
    final isTransport = _kind == 'transport';
    return AlertDialog(
      title: const Text('Add a booking'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'stay', child: Text('Stay')),
                DropdownMenuItem(value: 'transport', child: Text('Transport')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'stay'),
            ),
            TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title')),
            if (isTransport)
              TextField(
                  controller: _origin,
                  decoration:
                      const InputDecoration(labelText: 'Origin (optional)')),
            TextField(
                controller: _destination,
                decoration:
                    const InputDecoration(labelText: 'Destination (optional)')),
            TextField(
                controller: _departDate,
                decoration: InputDecoration(
                    labelText: isTransport
                        ? 'Depart date (YYYY-MM-DD)'
                        : 'Check-in (YYYY-MM-DD)')),
            if (!isTransport)
              TextField(
                  controller: _returnDate,
                  decoration: const InputDecoration(
                      labelText: 'Check-out (YYYY-MM-DD)')),
            TextField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'Link (optional, overrides search)')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Small pill showing a place's part of day (Morning/Afternoon/Evening), tinted
/// by time so a day's rhythm is scannable at a glance.
class _TimeOfDayChip extends StatelessWidget {
  final String timeOfDay;
  const _TimeOfDayChip({required this.timeOfDay});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (timeOfDay) {
      'morning' => ('Morning', Icons.wb_twilight),
      'afternoon' => ('Afternoon', Icons.wb_sunny_outlined),
      'evening' => ('Evening', Icons.nightlight_outlined),
      _ => (timeOfDay, Icons.schedule),
    };
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
