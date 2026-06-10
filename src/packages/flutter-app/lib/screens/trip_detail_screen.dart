import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/gradient_app_bar.dart';
import '../models/trip.dart';
import '../models/itinerary_item.dart';
import '../models/accommodation.dart';
import '../models/booking_todo.dart';
import '../models/location.dart';
import '../models/location_timing.dart';
import '../models/route_request.dart';
import '../providers/trips_provider.dart';
import '../providers/recent_trip_provider.dart';
import '../providers/booking_todos_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/api_client_provider.dart';
import '../providers/plan_provider.dart';
import '../widgets/add_itinerary_item_dialog.dart';
import '../widgets/booking_todo_card.dart';
import '../widgets/trip_map.dart';
import '../widgets/trip_refine_panel.dart';
import 'flight_search_screen.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  Trip? _trip;
  bool _loading = true;
  String? _error;
  // In-page AI refinement panel (side dock on wide layouts, bottom sheet on
  // narrow ones); null target while closed.
  bool _panelOpen = false;
  RefineTarget? _refineTarget;
  String _itemFilter = 'all'; // 'all' | 'attraction' | 'restaurant'
  int? _selectedPosition; // position of the place focused via a map pin / list tap
  List<BookingTodo> _bookingTodos = [];
  bool _overviewExpanded = false;
  // Collapsed sets (empty => all expanded). Cities keyed by group label; days
  // keyed by "<city>#<day>" since day numbers repeat across cities.
  final Set<String> _collapsedCities = {};
  final Set<String> _collapsedDays = {};
  String? _homeAirport; // traveler's saved home airport (IATA), for outbound/return flights
  // todo_key -> flight leg, so a transport booking item can open Find Flights prefilled.
  Map<String, ({String origin, String destination, String? date})> _flightLegs = {};
  // Per-leg travel timings keyed by the source item's position (the leg leaving
  // that item, to the next item in itinerary order). Empty until computed and on
  // any failure — travel times are an enhancement and never block the itinerary.
  Map<int, LocationTiming> _travelByPos = {};

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
        // Remember this as the most recently viewed trip (home screen tile).
        ref.read(recentTripProvider.notifier).record(trip.id, trip.title);
      }
      // Load the home airport so the booking checklist can derive the outbound
      // and return flights (no-op / null for anonymous sessions).
      await ref.read(preferencesProvider.notifier).load();
      _homeAirport = ref.read(preferencesProvider).prefs?.homeAirport;
      if (mounted && (trip.items ?? const []).isNotEmpty) {
        await _syncBookingTodos(trip);
        await _computeTravelTimes(trip);
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

  /// Computes per-leg travel times for the itinerary in its existing display
  /// order by calling /optimize-route in preserve-order mode (no reordering).
  /// Results are keyed by the source item's position; failures leave the map
  /// empty so the itinerary still renders.
  Future<void> _computeTravelTimes(Trip trip) async {
    final items = trip.items ?? const <ItineraryItem>[];
    final withCoords =
        items.where((i) => i.latitude != 0 || i.longitude != 0).length;
    if (withCoords < 2) return;
    try {
      final locations = [
        for (final it in items)
          Location(
            id: it.id,
            name: it.name,
            placeId: it.placeId,
            address: it.address,
            // (0,0) is the "no location" sentinel (e.g. manually added places
            // without a Places match) — send null so the optimizer skips the
            // coordinate rather than routing via the Gulf of Guinea.
            latitude: it.latitude == 0 && it.longitude == 0 ? null : it.latitude,
            longitude: it.latitude == 0 && it.longitude == 0 ? null : it.longitude,
            category: it.category,
          ),
      ];
      final resp = await ref.read(apiClientProvider).optimizeRoute(
            RouteRequest(
              locations: locations,
              returnToStart: false,
              preserveOrder: true,
            ),
          );
      final timings = resp.locationTimings;
      final map = <int, LocationTiming>{};
      for (var i = 0; i < items.length && i < timings.length; i++) {
        map[items[i].position] = timings[i];
      }
      if (mounted) setState(() => _travelByPos = map);
    } catch (_) {
      // Non-fatal: leave travel times empty.
    }
  }

  /// Builds the auto-TODO payload from the itinerary's location groups: a stay
  /// per city (with its dates) and a transport leg between consecutive cities.
  List<Map<String, dynamic>> _deriveTodos(Trip trip) {
    final ranges = _locationGroupRanges(trip);
    final todos = <Map<String, dynamic>>[];
    final legs = <String, ({String origin, String destination, String? date})>{};
    var pos = 0;
    final home = _homeAirport;
    final hasHome = home != null && home.isNotEmpty && ranges.isNotEmpty;

    // Adds a transport (flight) todo and records its leg so the booking item can
    // open Find Flights prefilled.
    void addFlight(String origin, String destination, DateTime? when) {
      final date = when == null ? null : _fmt(when);
      final key =
          'transport:${origin.toLowerCase()}>>${destination.toLowerCase()}';
      todos.add({
        'kind': 'transport',
        'todo_key': key,
        'title': '$origin → $destination',
        if (when != null) 'subtitle': _fmtShortDt(when),
        'provider': 'google_flights',
        'position': pos++,
        'origin': origin,
        'destination': destination,
        if (date != null) 'depart_date': date,
        'passengers': 1,
      });
      legs[key] = (origin: origin, destination: destination, date: date);
    }

    // Outbound: home airport -> first city, on the trip's start date.
    if (hasHome) {
      addFlight(home, ranges.first.label, ranges.first.start);
    }

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
        addFlight(label, ranges[i + 1].label, r.end);
      }
    }

    // Return: last city -> home airport, on the trip's end date.
    if (hasHome) {
      addFlight(ranges.last.label, home, ranges.last.end);
    }

    _flightLegs = legs;
    return todos;
  }

  /// Partitions [_bookingTodos] into per-city embedded slots — the flight that
  /// arrives at the city, its stay, and (for the last city) the return flight
  /// home — plus the residual list of everything that matched no city
  /// (user-added `custom:*` todos, stale auto todos). Each todo is claimed at
  /// most once, so repeated city labels still render each booking exactly once.
  ({
    List<({BookingTodo? arrival, BookingTodo? stay, BookingTodo? departure})> slots,
    List<BookingTodo> residual,
  }) _groupedBookings(List<String> groupLabels) {
    final claimed = <String>{};
    BookingTodo? claim(bool Function(BookingTodo) test) {
      for (final t in _bookingTodos) {
        if (!claimed.contains(t.id) && test(t)) {
          claimed.add(t.id);
          return t;
        }
      }
      return null;
    }

    final arrivals = <BookingTodo?>[];
    final stays = <BookingTodo?>[];
    for (final label in groupLabels) {
      final l = label.toLowerCase();
      arrivals.add(claim(
          (t) => t.kind == 'transport' && t.todoKey.endsWith('>>$l')));
      stays.add(claim((t) => t.todoKey == 'stay:$l'));
    }
    // Claimed after all arrivals so an inter-city leg can't be taken as its
    // origin's departure — only the final leg home remains unclaimed by then.
    BookingTodo? departure;
    if (groupLabels.isNotEmpty) {
      final last = groupLabels.last.toLowerCase();
      departure = claim((t) =>
          t.kind == 'transport' && t.todoKey.startsWith('transport:$last>>'));
    }

    return (
      slots: [
        for (var i = 0; i < groupLabels.length; i++)
          (
            arrival: arrivals[i],
            stay: stays[i],
            departure: i == groupLabels.length - 1 ? departure : null,
          ),
      ],
      residual:
          _bookingTodos.where((t) => !claimed.contains(t.id)).toList(),
    );
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

  Future<void> _addPlace() async {
    final trip = _trip;
    if (trip == null) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AddItineraryItemDialog(trip: trip),
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

  /// Opens the in-page refinement panel on [target], seeding a fresh session
  /// with the section's current contents. The session is bound to this trip
  /// server-side, so changes patch the trip in place (no new versions).
  void _openRefine(Trip trip, RefineTarget target) {
    final items = trip.items ?? [];
    if (items.isEmpty) {
      _showSnack('Add some places before refining with AI.');
      return;
    }
    ref
        .read(tripRefineProvider(widget.tripId).notifier)
        .beginSectionRefinement(_buildSectionSeed(trip, target));
    setState(() {
      _panelOpen = true;
      _refineTarget = target;
    });
  }

  /// Whether an item falls inside the refinement target (client-side mirror of
  /// the server's section selector, using the same hub grouping as the list).
  bool _inTarget(ItineraryItem it, RefineTarget t) {
    switch (t.scope) {
      case 'day':
        if (it.day != t.day) return false;
        return t.city == null ||
            (_hubOf(it)?.toLowerCase() == t.city!.toLowerCase());
      case 'city':
        return _hubOf(it)?.toLowerCase() == t.city!.toLowerCase();
      default:
        return true;
    }
  }

  /// One compact line per item with everything the agent must echo back to
  /// keep the item unchanged (coordinates and all tags).
  String _seedLine(ItineraryItem it) {
    final b = StringBuffer('- ${it.name}');
    if (it.category != null) b.write(' [${it.category}]');
    b.write(' (${it.latitude}, ${it.longitude})');
    final city = it.city?.trim();
    if (city != null && city.isNotEmpty) b.write(', city: $city');
    final hub = it.dayTripFrom?.trim();
    if (hub != null && hub.isNotEmpty) b.write(', day trip from $hub');
    if (it.day != null) b.write(', day ${it.day}');
    if (it.timeOfDay != null) b.write(', ${it.timeOfDay}');
    return b.toString();
  }

  /// Builds the panel's seed message: trip context, the target section's items
  /// in full detail, and explicit instructions to patch only that section via
  /// update_itinerary_section.
  String _buildSectionSeed(Trip trip, RefineTarget t) {
    final items = trip.items ?? [];
    final b = StringBuffer('I want to refine my saved trip "${_displayTitle(trip)}"');
    if (trip.startDate != null && trip.endDate != null) {
      b.write(' (${trip.startDate} to ${trip.endDate})');
    }
    b.writeln('.');

    final inTarget = items.where((it) => _inTarget(it, t)).toList();
    if (t.scope == 'trip') {
      b.writeln('\nThe full itinerary:');
    } else {
      // A one-line digest of the rest of the trip so the agent has context
      // without treating it as editable.
      b.writeln('\nFor context, the rest of the trip (do not change these): '
          '${items.where((it) => !_inTarget(it, t)).map((it) => it.name).join(', ')}.');
      b.writeln('\nThe section to refine — ${t.label}:');
    }
    for (final it in inTarget) {
      b.writeln(_seedLine(it));
    }

    b.write('\nOnly change this section unless I broaden the request. When you '
        'apply a change, call update_itinerary_section with ');
    switch (t.scope) {
      case 'day':
        b.write("scope='day', day=${t.day}");
        if (t.city != null) b.write(", city='${t.city}'");
      case 'city':
        b.write("scope='city', city='${t.city}'");
      default:
        b.write("scope='trip'");
    }
    b.write(' and the COMPLETE updated list for the section, keeping unchanged '
        'places exactly as listed above (same coordinates and tags). '
        'Start by asking what I want to change.');
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
        await ref.read(recentTripProvider.notifier).clearIfMatches(widget.tripId);
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

  /// Renders a hub group's items, split into "Day N" sub-sections when items
  /// carry day numbers (day-trip batching applied within each day). Legacy items
  /// with no day fall back to flat day-trip batching with no day headers.
  List<Widget> _buildGroupItemWidgets(String cityKey, List<ItineraryItem> items,
      ThemeData theme, DateTime? tripStart) {
    if (!items.any((it) => it.day != null)) {
      return _buildDayTripWidgets(items, theme);
    }
    final widgets = <Widget>[];
    var i = 0;
    while (i < items.length) {
      final day = items[i].day;
      final run = <ItineraryItem>[];
      while (i < items.length && items[i].day == day) {
        run.add(items[i]);
        i++;
      }
      if (day != null) {
        final dayKey = '$cityKey#$day';
        final collapsed = _collapsedDays.contains(dayKey);
        widgets.add(_daySubHeader(day, tripStart, theme, collapsed, _runTravelMin(run), () {
          setState(() {
            if (collapsed) {
              _collapsedDays.remove(dayKey);
            } else {
              _collapsedDays.add(dayKey);
            }
          });
        }, () {
          final trip = _trip;
          if (trip == null) return;
          // 'Other places' is a fallback label, not a real hub — omit the city
          // qualifier so the server matches on the day alone.
          _openRefine(
              trip,
              RefineTarget.day(day,
                  city: cityKey == 'Other places' ? null : cityKey));
        }));
        if (!collapsed) widgets.addAll(_buildDayTripWidgets(run, theme));
      } else {
        widgets.addAll(_buildDayTripWidgets(run, theme));
      }
    }
    return widgets;
  }

  /// Compact booking rows for a city group's slot: arrival flight + stay when
  /// [departureOnly] is false, the return-home flight when true.
  List<Widget> _bookingRowWidgets(
    ({BookingTodo? arrival, BookingTodo? stay, BookingTodo? departure}) slot, {
    required bool departureOnly,
  }) {
    final todos = departureOnly
        ? [slot.departure]
        : [slot.arrival, slot.stay];
    return [
      for (final todo in todos)
        if (todo != null)
          BookingTodoRow(
            todo: todo,
            onBookedChanged: (v) => _setBooked(todo, v),
            onOpen: _openCallbackFor(todo),
            openLabelOverride:
                _flightLegs.containsKey(todo.todoKey) ? 'Find flights' : null,
          ),
    ];
  }

  /// Batches consecutive day-trip places (by town) under an indented
  /// "Day trip · <town>" sub-header so nearby towns read as excursions from the
  /// hub city rather than separate stops. Inserts a within-city travel-time
  /// connector between adjacent tiles of the same indent run.
  List<Widget> _buildDayTripWidgets(List<ItineraryItem> items, ThemeData theme) {
    final widgets = <Widget>[];
    ItineraryItem? prev;
    void addTile(ItineraryItem it, double indent) {
      if (prev != null) {
        final connector = _travelConnector(prev!, it, indent, theme);
        if (connector != null) widgets.add(connector);
      }
      widgets.add(_itemTile(it, indent, theme));
      prev = it;
    }

    var i = 0;
    while (i < items.length) {
      final dt = items[i].dayTripFrom?.trim();
      if (dt != null && dt.isNotEmpty) {
        final town = _cityOf(items[i]) ?? 'Day trip';
        widgets.add(_dayTripSubHeader(town, theme, _dayTripTravelLabel(items[i])));
        prev = null; // don't draw a connector across the sub-header
        while (i < items.length) {
          final it = items[i];
          final d = it.dayTripFrom?.trim();
          if (d != null && d.isNotEmpty && _cityOf(it) == town) {
            addTile(it, 32);
            i++;
          } else {
            break;
          }
        }
        prev = null; // leaving the day-trip batch
      } else {
        addTile(items[i], 12);
        i++;
      }
    }
    return widgets;
  }

  /// A small "↓ 12 min · 4.3 km" row shown between two consecutive itinerary
  /// tiles, but only for within-city hops (same hub, truly adjacent in the
  /// itinerary order). Returns null when it shouldn't render — including while a
  /// category filter is active, since filtered tiles aren't globally adjacent.
  Widget? _travelConnector(
      ItineraryItem from, ItineraryItem to, double indentLeft, ThemeData theme) {
    if (_itemFilter != 'all') return null;
    if (to.position != from.position + 1) return null;
    if (_hubOf(from) != _hubOf(to)) return null;
    final timing = _travelByPos[from.position];
    if (timing == null || timing.travelToNextMin <= 0) return null;

    final km = timing.travelToNextKm;
    final dist = km > 0 ? ' · ${km.toStringAsFixed(1)} km' : '';
    final muted = theme.colorScheme.onSurfaceVariant;
    final icon = km > 0 && km <= 1.2
        ? Icons.directions_walk
        : Icons.directions_car_outlined;
    return Padding(
      padding: EdgeInsets.only(left: indentLeft + 28, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: muted),
          const SizedBox(width: 6),
          Text(
            '${_fmtTravel(timing.travelToNextMin)}$dist',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }

  /// Total within-city travel time (minutes) across the consecutive legs of a
  /// day's run. Zero while a category filter is active (legs aren't adjacent).
  int _runTravelMin(List<ItineraryItem> run) {
    if (_itemFilter != 'all') return 0;
    var total = 0;
    for (var k = 0; k < run.length - 1; k++) {
      final a = run[k];
      final b = run[k + 1];
      if (b.position == a.position + 1 && _hubOf(a) == _hubOf(b)) {
        total += _travelByPos[a.position]?.travelToNextMin ?? 0;
      }
    }
    return total;
  }

  /// Travel-time labels for the trip map, keyed by the source item's position:
  /// one entry per within-city leg (same hub, adjacent in itinerary order).
  /// Empty while a category filter is active (legs aren't globally adjacent).
  Map<int, String> _segmentLabels() {
    final trip = _trip;
    if (_itemFilter != 'all' || trip == null) return const {};
    final items = trip.items ?? const <ItineraryItem>[];
    final byPos = {for (final it in items) it.position: it};
    final out = <int, String>{};
    for (final it in items) {
      final next = byPos[it.position + 1];
      if (next == null || _hubOf(it) != _hubOf(next)) continue;
      final t = _travelByPos[it.position];
      if (t == null || t.travelToNextMin <= 0) continue;
      out[it.position] = _fmtTravel(t.travelToNextMin);
    }
    return out;
  }

  /// Travel time from the hub city to a day trip, e.g. "45 min from Paris",
  /// taken from the already-computed leg into the day trip's first stop. Null
  /// unless the preceding item is actually in the hub city (so a town-to-town
  /// or cross-city leg is never mislabeled), or while a category filter is
  /// active (filtered tiles aren't globally adjacent).
  String? _dayTripTravelLabel(ItineraryItem first) {
    if (_itemFilter != 'all') return null;
    final hub = first.dayTripFrom?.trim();
    if (hub == null || hub.isEmpty) return null;
    ItineraryItem? prev;
    for (final it in _trip?.items ?? const <ItineraryItem>[]) {
      if (it.position == first.position - 1) prev = it;
    }
    if (prev == null) return null;
    final prevDayTrip = prev.dayTripFrom?.trim();
    if (prevDayTrip != null && prevDayTrip.isNotEmpty) return null;
    if (_hubOf(prev) != _hubOf(first)) return null;
    final timing = _travelByPos[prev.position];
    if (timing == null || timing.travelToNextMin <= 0) return null;
    return '${_fmtTravel(timing.travelToNextMin)} from $hub';
  }

  /// Formats a travel duration: "45 min", "1h", or "1h 20m".
  String _fmtTravel(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// Day section header: shows the calendar date (day N -> startDate + (N-1))
  /// when the trip start is known, otherwise falls back to "Day N".
  Widget _daySubHeader(int day, DateTime? tripStart, ThemeData theme,
      bool collapsed, int travelMin, VoidCallback onTap, VoidCallback onRefine) {
    final label = tripStart != null
        ? _fmtDayHeader(tripStart.add(Duration(days: day - 1)))
        : 'Day $day';
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Row(
          children: [
            Icon(Icons.today, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (travelMin > 0) ...[
              Icon(Icons.directions_car_outlined, size: 14, color: muted),
              const SizedBox(width: 4),
              Text(
                '${_fmtTravel(travelMin)} travel',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.auto_awesome, size: 16),
              tooltip: 'Refine this day',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.primary,
              onPressed: onRefine,
            ),
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayTripSubHeader(String town, ThemeData theme, String? travelLabel) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
        child: Row(
          children: [
            Icon(Icons.directions_bus, size: 16, color: theme.colorScheme.secondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Day trip · $town',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (travelLabel != null) ...[
              Icon(Icons.directions_car_outlined, size: 14,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                travelLabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      );

  Widget _itemTile(ItineraryItem item, double indentLeft, ThemeData theme) => Padding(
        padding: EdgeInsets.only(left: indentLeft),
        child: ListTile(
          leading: _itemLeading(item.category, item.position),
          title: Text(item.name),
          subtitle: item.address != null ? Text(item.address!) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.timeOfDay != null)
                _TimeOfDayChip(timeOfDay: item.timeOfDay!),
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: 'Open in Google Maps',
                onPressed: () => _launch(_mapsUrl(item)),
              ),
            ],
          ),
          selected: _selectedPosition == item.position,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          // The map is pinned and always on screen, so tapping an item only
          // needs to update the selection; TripMap recenters on the new pin.
          onTap: () => setState(() => _selectedPosition = item.position),
        ),
      );

  /// Google Maps deep link for a place: prefer place_id, then coordinates, then a
  /// name/address text search.
  String _mapsUrl(ItineraryItem it) {
    const base = 'https://www.google.com/maps/search/?api=1';
    if (it.placeId != null && it.placeId!.isNotEmpty) {
      return '$base&query=${Uri.encodeComponent(it.name)}&query_place_id=${it.placeId}';
    }
    if (it.latitude != 0 || it.longitude != 0) {
      return '$base&query=${it.latitude},${it.longitude}';
    }
    return '$base&query=${Uri.encodeComponent('${it.name} ${it.address ?? ''}'.trim())}';
  }

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
      final dayRange = _dayRangeFor(g, start);
      final a = auto[i];
      result.add((
        label: locality ?? 'Other places',
        start: accRange?.start ?? dayRange?.start ?? a?.start,
        end: accRange?.end ?? dayRange?.end ?? a?.end,
      ));
    }
    return result;
  }

  /// Date range for a location group from its items' AI-assigned day numbers,
  /// anchored to the trip start: day N -> startDate + (N-1). Null when the trip
  /// has no start date or none of the items carry a day.
  ({DateTime start, DateTime end})? _dayRangeFor(
      List<ItineraryItem> items, DateTime? tripStart) {
    if (tripStart == null) return null;
    int? lo, hi;
    for (final it in items) {
      final d = it.day;
      if (d == null || d < 1) continue;
      if (lo == null || d < lo) lo = d;
      if (hi == null || d > hi) hi = d;
    }
    if (lo == null || hi == null) return null;
    return (
      start: tripStart.add(Duration(days: lo - 1)),
      end: tripStart.add(Duration(days: hi - 1)),
    );
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

  /// Day-header date, e.g. "Tue, Jul 15" (weekday + month + day).
  String _fmtDayHeader(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
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
                onPressed: () => _openRefine(trip, const RefineTarget.trip()),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Refine with AI'),
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
        title: Text(trip != null ? _displayTitle(trip) : 'Trip'),
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
                  : LayoutBuilder(builder: (context, constraints) {
                      // City-matched bookings render inside their city group;
                      // the rest fall through to the "Other bookings" section.
                      final grouped = _groupedBookings(
                          [for (final r in _locationGroupRanges(trip)) r.label]);
                      final scrollView = CustomScrollView(
                        slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeaderCard(trip, theme),
                                const Divider(height: 32),
                              ],
                            ),
                          ),
                        ),
                        // The map scrolls with the page until it reaches the top,
                        // then stays pinned while the itinerary scrolls beneath it.
                        if (_filtered(trip).any((i) => i.latitude != 0 || i.longitude != 0))
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _PinnedHeaderDelegate(
                              height: 12 + 240 + 12, // top gap + map + bottom gap
                              backgroundColor: theme.scaffoldBackgroundColor,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: TripMap(
                                  items: _filtered(trip),
                                  selectedPosition: _selectedPosition,
                                  segmentLabels: _segmentLabels(),
                                  onPinTap: (pos) {
                                    setState(() => _selectedPosition = pos);
                                    final it = trip.items!.firstWhere((i) => i.position == pos);
                                    _showSnack(it.name);
                                  },
                                ),
                              ),
                            ),
                          ),
                        // Itinerary title + category filter; pins beneath the
                        // map so the filter stays reachable while scrolling.
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _PinnedHeaderDelegate(
                            // title row (36) + gap (8) + chip row (48) + bottom
                            // padding (8); title-row-only when there are no items.
                            height:
                                (trip.items ?? const []).isNotEmpty ? 100 : 48,
                            backgroundColor: theme.scaffoldBackgroundColor,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            // Align fills the header's full extent so the child's
                            // measured height matches maxExtent (a min-sized
                            // Column would be shorter, yielding an invalid sliver
                            // geometry: layoutExtent > paintExtent).
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 36,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text('Itinerary',
                                              style:
                                                  theme.textTheme.titleMedium),
                                        ),
                                        TextButton.icon(
                                          onPressed: _addPlace,
                                          style: TextButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('Add place'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if ((trip.items ?? const []).isNotEmpty) ...[
                                    const SizedBox(height: 8),
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
                                            onSelected: (_) => setState(
                                                () => _itemFilter = f.$1),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
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
                                        for (final (gi, group)
                                            in groups.indexed) ...[
                                          Builder(builder: (_) {
                                            final cityCollapsed =
                                                _collapsedCities.contains(group.label);
                                            return InkWell(
                                              onTap: () => setState(() {
                                                if (cityCollapsed) {
                                                  _collapsedCities.remove(group.label);
                                                } else {
                                                  _collapsedCities.add(group.label);
                                                }
                                              }),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(16, 16, 16, 4),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Icon(Icons.location_on,
                                                            size: 18,
                                                            color: theme.colorScheme.primary),
                                                        const SizedBox(width: 6),
                                                        Expanded(
                                                          child: Text(
                                                            group.label,
                                                            style: theme.textTheme.titleSmall
                                                                ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight.bold),
                                                          ),
                                                        ),
                                                        if (group.dateRange != null) ...[
                                                          Icon(Icons.event,
                                                              size: 14,
                                                              color:
                                                                  theme.colorScheme.primary),
                                                          const SizedBox(width: 4),
                                                          Text(
                                                            group.dateRange!,
                                                            style: theme.textTheme.labelMedium
                                                                ?.copyWith(
                                                                    color: theme
                                                                        .colorScheme.primary),
                                                          ),
                                                        ],
                                                        // 'Other places' has no hub the
                                                        // section tool can target.
                                                        if (group.label != 'Other places')
                                                          IconButton(
                                                            icon: const Icon(
                                                                Icons.auto_awesome,
                                                                size: 16),
                                                            tooltip:
                                                                'Refine ${group.label}',
                                                            visualDensity:
                                                                VisualDensity.compact,
                                                            color: theme
                                                                .colorScheme.primary,
                                                            onPressed: () => _openRefine(
                                                                trip,
                                                                RefineTarget.city(
                                                                    group.label)),
                                                          ),
                                                        const SizedBox(width: 4),
                                                        Icon(
                                                          cityCollapsed
                                                              ? Icons.chevron_right
                                                              : Icons.expand_more,
                                                          size: 20,
                                                          color: theme.colorScheme.primary,
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 4),
                                                    const Divider(height: 1),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                          if (!_collapsedCities.contains(group.label)) ...[
                                            // Embedded bookings render only in the
                                            // unfiltered view: a category filter can
                                            // merge adjacent same-label runs, which
                                            // would break the slot<->group mapping.
                                            if (_itemFilter == 'all' &&
                                                gi < grouped.slots.length)
                                              ..._bookingRowWidgets(
                                                  grouped.slots[gi],
                                                  departureOnly: false),
                                            ..._buildGroupItemWidgets(
                                                group.label,
                                                group.items,
                                                theme,
                                                DateTime.tryParse(trip.startDate ?? '')),
                                            if (_itemFilter == 'all' &&
                                                gi == groups.length - 1 &&
                                                gi < grouped.slots.length)
                                              ..._bookingRowWidgets(
                                                  grouped.slots[gi],
                                                  departureOnly: true),
                                          ],
                                        ],
                                      ],
                                    );
                                  }),
                                // Bookings live embedded in their city groups;
                                // this section appears only when something
                                // didn't match a city (custom or stale todos).
                                if (grouped.residual.isEmpty)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      onPressed: _addBooking,
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Add booking'),
                                    ),
                                  )
                                else ...[
                                  const Divider(height: 32),
                                  Row(
                                    children: [
                                      Expanded(child: Text('Other bookings', style: theme.textTheme.titleMedium)),
                                      TextButton.icon(
                                        onPressed: _addBooking,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Add'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  for (final todo in grouped.residual)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      child: BookingTodoCard(
                                        todo: todo,
                                        onBookedChanged: (v) => _setBooked(todo, v),
                                        onOpen: _openCallbackFor(todo),
                                        openLabelOverride:
                                            _flightLegs.containsKey(todo.todoKey)
                                                ? 'Find flights'
                                                : null,
                                        onDelete:
                                            todo.auto ? null : () => _deleteTodo(todo),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );

                      if (!_panelOpen || _refineTarget == null) {
                        return scrollView;
                      }
                      final panel = TripRefinePanel(
                        tripId: widget.tripId,
                        target: _refineTarget!,
                        onClose: () => setState(() => _panelOpen = false),
                        onTripUpdated: _load,
                      );
                      if (constraints.maxWidth >= 900) {
                        // Wide: dock the chat beside the itinerary.
                        return Row(
                          children: [
                            Expanded(child: scrollView),
                            const VerticalDivider(width: 1),
                            SizedBox(width: 400, child: panel),
                          ],
                        );
                      }
                      // Narrow: collapsible bottom sheet over the page; bottom
                      // inset keeps the input above the keyboard.
                      return Stack(
                        children: [
                          scrollView,
                          DraggableScrollableSheet(
                            initialChildSize: 0.45,
                            minChildSize: 0.15,
                            maxChildSize: 0.92,
                            snap: true,
                            builder: (context, scrollController) => Material(
                              elevation: 8,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16)),
                              clipBehavior: Clip.antiAlias,
                              child: Padding(
                                padding: EdgeInsets.only(
                                    bottom:
                                        MediaQuery.of(context).viewInsets.bottom),
                                child: Column(
                                  children: [
                                    // Drag handle (also a scrollable so the
                                    // sheet responds to drags at its header).
                                    SingleChildScrollView(
                                      controller: scrollController,
                                      child: Center(
                                        child: Container(
                                          width: 36,
                                          height: 4,
                                          margin: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.outlineVariant,
                                            borderRadius:
                                                BorderRadius.circular(2),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(child: panel),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
    );
  }

  /// The open action for a booking item: a transport item with a known flight
  /// leg opens the in-app Find Flights screen prefilled; everything else falls
  /// back to its external provider search link.
  VoidCallback? _openCallbackFor(BookingTodo todo) {
    final leg = todo.kind == 'transport' ? _flightLegs[todo.todoKey] : null;
    if (leg != null) {
      return () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FlightSearchScreen(
              prefillOrigin: leg.origin,
              prefillDestination: leg.destination,
              prefillDepartDate: leg.date,
            ),
          ));
    }
    if (todo.searchUrl != null) return () => _launch(todo.searchUrl!);
    return null;
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

/// A fixed-height header that scrolls with the page until it reaches the top,
/// then stays pinned. Used for the trip map and, stacked beneath it, the
/// itinerary filter bar. The opaque [backgroundColor] fill keeps list content
/// from peeking through the [padding] (side margins and gaps) while pinned.
class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Color backgroundColor;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _PinnedHeaderDelegate({
    required this.height,
    required this.backgroundColor,
    required this.padding,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(
        color: backgroundColor,
        padding: padding,
        child: child,
      );

  @override
  bool shouldRebuild(_PinnedHeaderDelegate oldDelegate) =>
      oldDelegate.child != child ||
      oldDelegate.height != height ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.padding != padding;
}
