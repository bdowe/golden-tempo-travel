import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/gradient_app_bar.dart';
import '../models/trip.dart';
import '../models/itinerary_item.dart';
import '../models/accommodation.dart';
import '../models/booking_todo.dart';
import '../models/local_guide.dart';
import '../models/location.dart';
import '../models/location_timing.dart';
import '../models/route_request.dart';
import '../models/trip_segment.dart';
import '../providers/accommodations_provider.dart';
import '../providers/transport_provider.dart';
import '../providers/trips_provider.dart';
import '../providers/recent_trip_provider.dart';
import '../providers/booking_drafts_provider.dart';
import '../providers/booking_todos_provider.dart';
import '../providers/preferences_provider.dart';
import '../providers/api_client_provider.dart';
import '../providers/plan_provider.dart';
import '../providers/events_provider.dart';
import '../providers/ferries_provider.dart';
import '../providers/local_provider.dart';
import '../providers/shared_with_me_provider.dart';
import '../providers/trip_cache_provider.dart';
import '../services/trip_cache.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../utils/share_link.dart';
import '../utils/tracked_launch.dart';
import '../utils/trip_days.dart';
import '../utils/trip_format.dart';
import '../widgets/add_itinerary_item_dialog.dart';
import '../widgets/add_to_trip_sheet.dart';
import '../widgets/booking_todo_card.dart';
import '../widgets/bookings_section.dart';
import '../widgets/empty_state.dart';
import '../widgets/event_card.dart';
import '../widgets/local_rec_card.dart';
import '../widgets/map_day_chips.dart';
import '../widgets/offline_banner.dart';
import '../widgets/source_links_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_map.dart';
import '../widgets/trip_refine_panel.dart';
import 'flight_search_screen.dart';
import 'local_guide_detail_screen.dart';
import '../utils/snack.dart';

/// A geographic coordinate used to resolve an itinerary place to its nearest
/// bookable airport when the place name has no IATA match.
typedef _Coord = ({double lat, double lng});

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen>
    with WidgetsBindingObserver {
  Trip? _trip;
  bool _loading = true;
  String? _error;
  // Non-null while _trip is a cached copy served because the network was
  // unreachable (value = when the copy was saved). The screen is read-only
  // in this mode; a successful live load clears it.
  DateTime? _offlineSince;
  // In-page AI refinement panel (side dock on wide layouts, bottom sheet on
  // narrow ones); null target while closed.
  bool _panelOpen = false;
  RefineTarget? _refineTarget;
  String _itemFilter = 'all'; // 'all' | 'attraction' | 'restaurant'
  int? _selectedDay; // map day-chip selection; null = All (specs/today-mode)
  // Today mode (specs/today-mode): the itinerary auto-scrolls to today's day
  // header at most once per screen visit, and only from loud load paths.
  final ScrollController _scroll = ScrollController();
  bool _autoScrolledToday = false;
  // Day set by a loud load, consumed by the first build that has the scroll
  // view on screen (the load's own setState still shows the loading spinner,
  // so the scroll can't be kicked off from there).
  int? _pendingTodayScroll;
  // Stable identities for the pinned headers so the Today scroller can find
  // their render objects. Days share the `'$cityKey#$day'` scheme with
  // _collapsedDays; cities are keyed by group label like _collapsedCities.
  final Map<String, GlobalKey> _dayHeaderKeys = {};
  final Map<String, GlobalKey> _cityHeaderKeys = {};
  int?
      _selectedPosition; // position of the place focused via a map pin / list tap
  List<BookingTodo> _bookingTodos = [];
  // Sync-owned copies of the trip's stays/segments (drafts + confirmed), like
  // _bookingTodos: the booking-drafts sync replaces them after each trip load
  // without rebuilding the immutable Trip.
  List<Accommodation> _stays = [];
  List<TripSegment> _segments = [];
  bool _overviewExpanded = false;
  // Collapsed sets (empty => all expanded). Cities keyed by group label; days
  // keyed by "<city>#<day>" since day numbers repeat across cities.
  final Set<String> _collapsedCities = {};
  final Set<String> _collapsedDays = {};
  String?
      _homeAirport; // traveler's saved home airport (IATA), for outbound/return flights
  // todo_key -> flight leg, so a transport booking item can open Find Flights
  // prefilled. Coords resolve an endpoint to its nearest airport when the city
  // label has no IATA match (e.g. a village like Imerovigli -> Santorini/JTR).
  Map<String,
          ({
            String origin,
            String destination,
            String? date,
            _Coord? originCoord,
            _Coord? destCoord
          })> _flightLegs =
      {};
  // todo_key -> ferry leg (Greek port<->port), so the booking item opens the
  // Ferryhopper search for that route instead of a flight.
  Map<String, ({String origin, String destination, String? date})> _ferryLegs =
      {};
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

  /// [_filtered] further narrowed to the selected map day chip. The map is
  /// the only consumer — the itinerary list never day-filters. Untagged
  /// items (day == null) show only under All.
  List<ItineraryItem> _dayFiltered(Trip trip) {
    return _filtered(trip)
        .where((i) => _selectedDay == null || i.day == _selectedDay)
        .toList();
  }

  /// The trip's user-confirmed stays. Suggested drafts (auto=true) are working
  /// state for the bookings hub only — they must never feed the map, the
  /// Tonight caption, or (crucially) [_locationGroupRanges]: seeded draft
  /// dates flowing back into derivation would freeze the derived ranges.
  List<Accommodation> _confirmedStays(Trip trip) =>
      (trip.accommodations ?? const <Accommodation>[])
          .where((a) => !a.auto)
          .toList();

  /// Stays the map should plot for the selected day chip: under All, every
  /// stay; under Day N, only stays covering that night (checkout-exclusive).
  /// A trip without a parseable start date can't map Day N to a calendar
  /// date, so no stay matches (they all still show under All).
  List<Accommodation> _dayFilteredStays(Trip trip) {
    final day = _selectedDay;
    if (day == null) return _confirmedStays(trip);
    return _staysOnNight(trip, day);
  }

  /// Stays covering the night of trip day [day], checkout-exclusively — the
  /// single home of the day→night math shared by the map's day filter and the
  /// Tonight caption. A trip without a parseable start date can't map Day N
  /// to a calendar date, so no stay matches.
  List<Accommodation> _staysOnNight(Trip trip, int day) {
    final all = _confirmedStays(trip);
    final start = DateTime.tryParse(trip.startDate ?? '');
    if (start == null) return const [];
    // Calendar-day arithmetic (constructor normalizes overflow) rather than
    // Duration, which drifts a date across a DST transition.
    final night = DateTime(start.year, start.month, start.day + day - 1);
    return all
        .where((a) => stayCoversDate(a.checkIn, a.checkOut, night))
        .toList();
  }

  /// Map-visibility gate: a filtered item with coordinates OR a geocoded stay
  /// (TripMap renders stay pins on its own, so a stays-only trip still has a
  /// map worth showing). Keyed to the unfiltered stay list — like the items,
  /// day filtering only narrows what's plotted, never whether the map shows.
  /// Shared by the build and the pinned-chrome scroll math so the two can
  /// never drift apart.
  bool _mapShown(Trip trip) =>
      _filtered(trip).any((i) => i.latitude != 0 || i.longitude != 0) ||
      _confirmedStays(trip).any(TripMap.stayHasCoords);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusPoll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // ── Freshness polling (specs/shared-trip-freshness) ───────────────────
  // Shared trips poll the cheap /status endpoint and silently refresh when
  // someone else edited. Only runs foregrounded, online, on shared trips.

  Timer? _statusPoll;
  static const _statusPollInterval = Duration(seconds: 25);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncStatusPolling();
      _statusTick(); // catch up on edits made while backgrounded
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _statusPoll?.cancel();
      _statusPoll = null;
    }
  }

  /// (Re)starts or stops the poll timer to match the loaded trip. Owners
  /// poll when the trip has co-planners (`shared`); editors and viewer
  /// follows always.
  void _syncStatusPolling() {
    final trip = _trip;
    final want = trip != null &&
        !_isOffline &&
        (!trip.isOwner || (trip.shared ?? false));
    if (want) {
      _statusPoll ??=
          Timer.periodic(_statusPollInterval, (_) => _statusTick());
    } else {
      _statusPoll?.cancel();
      _statusPoll = null;
    }
  }

  Future<void> _statusTick() async {
    final trip = _trip;
    // Skip while the refine panel streams (its trip_updated events already
    // drive _refresh) or a refresh is in flight.
    if (trip == null || _isOffline || _panelOpen || _refreshFuture != null) {
      return;
    }
    try {
      final status =
          await ref.read(tripsApiServiceProvider).getTripStatus(trip.id);
      if (!mounted) return;
      final loaded = DateTime.tryParse(trip.updatedAt);
      if (loaded != null && status.updatedAt.isAfter(loaded)) {
        await _refresh();
      }
    } catch (_) {
      // Background poll: never surface errors or flip offline mode.
    }
  }

  Future<void> _load({bool silent = false}) async {
    // Silent mode refreshes an already-displayed trip in place — no
    // full-screen spinner, no error page — so the refine panel (and the
    // conversation streaming inside it) stays mounted. First load always
    // takes the loud path.
    final quiet = silent && _trip != null;
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final trip =
          await ref.read(tripsApiServiceProvider).getTrip(widget.tripId);
      if (mounted) {
        // Write-through for offline viewing; fire-and-forget (never throws)
        // so the online path is unaffected.
        unawaited(ref.read(tripCacheProvider).writeTrip(trip));
        setState(() {
          _trip = trip;
          _bookingTodos = trip.bookingTodos ?? [];
          _stays = trip.accommodations ?? [];
          _segments = trip.segments ?? [];
          _offlineSince = null; // live data — leave offline mode if we were in it
          // Today mode fires only from loud loads — never from a silent
          // refresh, which shares this success path (PR #51/#53 invariants).
          if (!silent) _maybeAutoScrollToday(trip);
        });
        // Remember this as the most recently viewed trip (home screen tile).
        ref.read(recentTripProvider.notifier).record(
              trip.id,
              trip.title,
              dateRange: tripDateRange(trip.startDate, trip.endDate),
              status: trip.status,
            );
      }
      // Load the home airport so the booking checklist can derive the outbound
      // and return flights (no-op / null for anonymous sessions).
      await ref.read(preferencesProvider.notifier).load();
      _homeAirport = ref.read(preferencesProvider).prefs?.homeAirport;
      if (mounted && (trip.items ?? const []).isNotEmpty) {
        await _syncBookingTodos(trip);
        await _syncBookingDrafts(trip);
        await _computeTravelTimes(trip);
      }
    } catch (e) {
      // Loud path + network-level failure: fall back to the cached copy and
      // render it read-only. HTTP errors (403/404/500) never reach here —
      // isNetworkError excludes them — so a revoked or deleted trip can't
      // resurrect from a stale copy.
      if (mounted && !quiet && TripCache.isNetworkError(e)) {
        final cached = await ref.read(tripCacheProvider).readTrip(widget.tripId);
        if (cached != null && mounted) {
          setState(() {
            _trip = cached.trip;
            _bookingTodos = cached.trip.bookingTodos ?? [];
            _stays = cached.trip.accommodations ?? [];
            _segments = cached.trip.segments ?? [];
            _offlineSince = cached.savedAt;
            _error = null;
            // Opening a live trip while offline is Today mode's prime use
            // case — the cached copy scrolls to today just like a live load.
            if (!silent) _maybeAutoScrollToday(cached.trip);
          });
          return; // finally still clears _loading
        }
      }
      // Quiet path + network-level failure on the trip already on screen
      // (pull-to-refresh while offline): flip into offline mode — banner +
      // mutation guards — instead of completing the indicator silently with
      // edits still armed. The on-screen trip is at least as fresh as the
      // cache (every successful load writes through), so keep it; only the
      // offline state changes. Skipped while the refine panel is open: its
      // quiet refreshes are driven by trip_updated events on a live SSE
      // stream, so declaring the app offline mid-conversation would
      // contradict the working connection and strand the panel (which is
      // never allowed to observe offline mode — see _openRefine). Quiet
      // NON-network failures stay fully silent: a transient server error
      // during a streaming turn must not flash error UI (PR #51/#53).
      if (mounted &&
          quiet &&
          !_panelOpen &&
          _trip?.id == widget.tripId &&
          TripCache.isNetworkError(e)) {
        final cached =
            await ref.read(tripCacheProvider).readTrip(widget.tripId);
        if (mounted) {
          // The cache entry's timestamp is when the on-screen data was
          // fetched (write-through); fall back to "now" on a cache miss.
          setState(() => _offlineSince = cached?.savedAt ?? DateTime.now());
        }
        return;
      }
      if (mounted && !quiet) setState(() => _error = e.toString());
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
      if (mounted) _syncStatusPolling();
    }
  }

  bool get _isOffline => _offlineSince != null;

  /// Viewer follows (access == 'viewer') see the trip without any edit
  /// affordances — the server 404s their mutations anyway.
  bool get _readOnly => !(_trip?.canEdit ?? true);

  /// Belt-and-braces offline gate at the top of every mutation method. The
  /// primary affordances are also visually disabled/hidden while offline;
  /// this covers deep entry points (item menus, todo cards, per-day refine
  /// icons) without touching their widget subtrees.
  bool _guardOffline() {
    if (!_isOffline) return false;
    _showSnack("You're offline — reconnect to make changes.");
    return true;
  }

  bool _refreshQueued = false;
  Future<void>? _refreshFuture;

  /// Silent in-place reload with trailing coalescing. The server can emit
  /// several `trip_updated` events in one streaming turn; a bump that lands
  /// mid-fetch queues exactly one more pass so the final state always
  /// reflects the last patch. Concurrent user-driven `_load()` calls
  /// (add/edit/delete flows) are a pre-existing last-write-wins race and are
  /// not handled here.
  Future<void> _refresh() {
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      _refreshQueued = true;
      return inFlight;
    }
    final future = () async {
      do {
        _refreshQueued = false;
        await _load(silent: true);
      } while (mounted && _refreshQueued);
      _refreshFuture = null;
    }();
    _refreshFuture = future;
    return future;
  }

  // ── Today mode (specs/today-mode) ─────────────────────────────────────

  /// Pinned-header heights, shared by the build method and the Today scroll
  /// math so the two can never drift apart.
  static const double _mapHeaderHeight =
      12 + 240 + 12; // top gap + map + bottom gap
  // Itinerary title row (36) + gap (8) + filter chip row (48) + bottom
  // padding (8); title-row-only when the trip has no items.
  static const double _listHeaderHeight = 100;
  static const double _listHeaderHeightEmpty = 48;

  /// Combined height of the chrome pinned above the itinerary slivers: the
  /// map header (shown when a filtered item or a stay is mappable — same
  /// [_mapShown] gate as the build) plus the itinerary title/filter header.
  double _pinnedChrome(Trip trip) {
    final mapShown = _mapShown(trip);
    final listH = (trip.items ?? const []).isNotEmpty
        ? _listHeaderHeight
        : _listHeaderHeightEmpty;
    return (mapShown ? _mapHeaderHeight : 0) + listH;
  }

  /// Measured height of the pinned city header above [dayKey]'s section
  /// (0 when it isn't laid out yet).
  double _cityHeaderHeight(String dayKey) {
    final cityKey = dayKey.substring(0, dayKey.lastIndexOf('#'));
    final box = _cityHeaderKeys[cityKey]?.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.size.height : 0;
  }

  /// One-shot Today trigger, called inside the setState of the loud load
  /// paths (live success and cached-offline fallback) so the map's today
  /// chip preselection lands in the same frame as the trip. Never called
  /// from silent refreshes; a no-op once fired, while the refine panel is
  /// open, or when the trip is undated/past/future or has no day tags.
  void _maybeAutoScrollToday(Trip trip) {
    if (_autoScrolledToday || _panelOpen) return;
    final today = tripDayOn(trip.startDate, trip.endDate, DateTime.now());
    if (today == null) return;
    if (!(trip.items ?? const <ItineraryItem>[]).any((i) => i.day != null)) {
      return;
    }
    _autoScrolledToday = true;
    _selectedDay = today; // map day-chip preselect
    // The scroll itself waits for the first build that actually shows the
    // scroll view: this setState still renders the loading spinner (the
    // loud path clears _loading later, in its finally), so a post-frame
    // callback scheduled here could fire before the CustomScrollView exists.
    _pendingTodayScroll = today;
  }

  /// Scrolls the itinerary so [day]'s header rests just below the pinned
  /// chrome (map + title + city header). Missing headers fall back to the
  /// nearest prior day, then the nearest following; a collapsed city/day is
  /// expanded first. Pure view work — safe offline and with the panel open.
  void _scrollToDay(int day) {
    final dayKey = _resolveDayHeaderKey(day);
    if (dayKey == null) return;
    final cityKey = dayKey.substring(0, dayKey.lastIndexOf('#'));
    if (_collapsedCities.contains(cityKey) ||
        _collapsedDays.contains(dayKey)) {
      setState(() {
        _collapsedCities.remove(cityKey);
        _collapsedDays.remove(dayKey);
      });
      // Continue once the expanded section has laid out.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToDayHeader(dayKey));
      return;
    }
    _scrollToDayHeader(dayKey);
  }

  /// The registry key of the day header [day] should scroll to: the first
  /// (build-order) header for that exact day, else the nearest prior day
  /// with a header, else the nearest following. Only headers that are
  /// currently built count, except those hidden inside a collapsed city —
  /// still reachable because [_scrollToDay] expands them first.
  String? _resolveDayHeaderKey(int day) {
    String? prior;
    String? next;
    int? priorDay;
    int? nextDay;
    for (final entry in _dayHeaderKeys.entries) {
      final key = entry.key;
      final hashAt = key.lastIndexOf('#');
      final d = int.tryParse(key.substring(hashAt + 1));
      if (d == null) continue;
      // Skip stale keys whose day no longer renders (removed items), as
      // opposed to ones merely hidden inside a collapsed city group.
      if (entry.value.currentContext == null &&
          !_collapsedCities.contains(key.substring(0, hashAt))) {
        continue;
      }
      if (d == day) return key;
      if (d < day && (priorDay == null || d > priorDay)) {
        priorDay = d;
        prior = key;
      }
      if (d > day && (nextDay == null || d < nextDay)) {
        nextDay = d;
        next = key;
      }
    }
    return prior ?? next;
  }

  /// Offset-reveal scroll to [dayKey]'s header (specs/today-mode plan.md,
  /// D1): `ensureVisible` is unreliable under SliverPinnedHeader /
  /// MultiSliver, so compute the reveal offset, subtract everything pinned
  /// above the header's resting slot, animate, then run exactly one
  /// correction pass against the header's actual on-screen position.
  Future<void> _scrollToDayHeader(String dayKey) async {
    final trip = _trip;
    if (!mounted || trip == null || !_scroll.hasClients) return;
    final target = _dayHeaderKeys[dayKey]?.currentContext?.findRenderObject();
    if (target == null || !target.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(target);
    if (viewport == null) return;
    final resting = _pinnedChrome(trip) + _cityHeaderHeight(dayKey);
    final reveal = viewport.getOffsetToReveal(target, 0).offset - resting;
    final offset = reveal.clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(offset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic);
    if (!mounted || !_scroll.hasClients) return;
    // One correction pass (no loops chasing layout): late-built slivers can
    // shift the estimate, so measure where the header actually landed and
    // jump the residual. A header pinned in its slot measures exactly at
    // the desired dy, so this never fights the pin.
    final box = _dayHeaderKeys[dayKey]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final vp = RenderAbstractViewport.maybeOf(box);
    if (vp == null) return;
    // Header dy in viewport coordinates vs. its resting slot below the
    // pinned chrome.
    final actual = box.localToGlobal(Offset.zero, ancestor: vp).dy;
    final delta = actual - (_pinnedChrome(trip) + _cityHeaderHeight(dayKey));
    if (delta.abs() > 2) {
      _scroll.jumpTo((_scroll.offset + delta)
          .clamp(0.0, _scroll.position.maxScrollExtent));
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

  /// Pushes the itinerary-derived draft stays/transports for the bookings hub.
  /// The server upserts them as Suggested (auto) rows — never touching
  /// confirmed rows or dismissed drafts — prunes drafts whose legs no longer
  /// exist, and returns the fresh lists.
  Future<void> _syncBookingDrafts(Trip trip) async {
    try {
      final result = await ref
          .read(bookingDraftsApiServiceProvider)
          .syncDrafts(trip.id, _deriveBookingDrafts(trip));
      if (mounted) {
        setState(() {
          _stays = result.stays;
          _segments = result.segments;
        });
      }
    } catch (_) {
      // Non-fatal: keep whatever stays/segments came with the trip.
    }
  }

  /// Builds the booking-drafts payload from the same location-group ranges the
  /// checklist derives from (same key grammar too, so the two stay in
  /// lockstep): a stay per city and a transport leg between consecutive
  /// cities, plus home-airport outbound/return. Legs already covered by a
  /// confirmed (user-entered) row are skipped so drafts never duplicate real
  /// bookings.
  Map<String, dynamic> _deriveBookingDrafts(Trip trip) {
    final ranges = _locationGroupRanges(trip);
    final confirmedStays = _confirmedStays(trip);
    final confirmedSegments = (trip.segments ?? const <TripSegment>[])
        .where((s) => !s.auto)
        .toList();

    // A confirmed stay covers a city when it carries the draft's key (it was
    // confirmed from that draft) or its name/address mentions the city label
    // (same contains-matching as _accDateRangeFor).
    bool stayCovered(String key, String label) {
      final l = label.toLowerCase();
      for (final a in confirmedStays) {
        if (a.autoKey == key) return true;
        for (final field in [a.name, a.address]) {
          final f = field?.toLowerCase();
          if (f != null && f.isNotEmpty && (f.contains(l) || l.contains(f))) {
            return true;
          }
        }
      }
      return false;
    }

    bool transportCovered(String key, String origin, String destination) {
      final o = origin.toLowerCase();
      final d = destination.toLowerCase();
      for (final s in confirmedSegments) {
        if (s.autoKey == key) return true;
        if (s.origin?.toLowerCase() == o && s.destination?.toLowerCase() == d) {
          return true;
        }
      }
      return false;
    }

    final stays = <Map<String, dynamic>>[];
    final transports = <Map<String, dynamic>>[];

    void addLeg(String origin, String destination, DateTime? when) {
      final key =
          'transport:${origin.toLowerCase()}>>${destination.toLowerCase()}';
      if (transportCovered(key, origin, destination)) return;
      transports.add({
        'auto_key': key,
        'mode': _isGreekIsland(origin) && _isGreekIsland(destination)
            ? 'ferry'
            : 'flight',
        'origin': origin,
        'destination': destination,
        if (when != null) 'depart_date': _fmt(when),
      });
    }

    final home = _homeAirport;
    final hasHome = home != null && home.isNotEmpty && ranges.isNotEmpty;
    if (hasHome) addLeg(home, ranges.first.label, ranges.first.start);
    for (var i = 0; i < ranges.length; i++) {
      final r = ranges[i];
      final key = 'stay:${r.label.toLowerCase()}';
      if (!stayCovered(key, r.label)) {
        stays.add({
          'auto_key': key,
          'name': 'Stay in ${r.label}',
          'address': r.label,
          if (r.start != null) 'check_in': _fmt(r.start!),
          if (r.end != null) 'check_out': _fmt(r.end!),
        });
      }
      if (i < ranges.length - 1) addLeg(r.label, ranges[i + 1].label, r.end);
    }
    if (hasHome) addLeg(ranges.last.label, home, ranges.last.end);

    return {'stays': stays, 'transports': transports};
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
            latitude:
                it.latitude == 0 && it.longitude == 0 ? null : it.latitude,
            longitude:
                it.latitude == 0 && it.longitude == 0 ? null : it.longitude,
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
    final legs = <String,
        ({
          String origin,
          String destination,
          String? date,
          _Coord? originCoord,
          _Coord? destCoord
        })>{};
    final ferryLegs =
        <String, ({String origin, String destination, String? date})>{};
    var pos = 0;
    final home = _homeAirport;
    final hasHome = home != null && home.isNotEmpty && ranges.isNotEmpty;

    // Adds a transport (flight) todo and records its leg so the booking item can
    // open Find Flights prefilled. Coords (when known) resolve an endpoint to its
    // nearest airport if the city label itself has no IATA match.
    void addFlight(String origin, String destination, DateTime? when,
        {_Coord? originCoord, _Coord? destCoord}) {
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
      legs[key] = (
        origin: origin,
        destination: destination,
        date: date,
        originCoord: originCoord,
        destCoord: destCoord,
      );
    }

    // Adds a transport (ferry) todo for a Greek port<->port leg and records it so
    // the booking item opens the Ferryhopper search for that route.
    void addFerry(String origin, String destination, DateTime? when) {
      final date = when == null ? null : _fmt(when);
      final key =
          'transport:${origin.toLowerCase()}>>${destination.toLowerCase()}';
      todos.add({
        'kind': 'transport',
        'todo_key': key,
        'title': '$origin → $destination',
        if (when != null) 'subtitle': _fmtShortDt(when),
        'provider': 'ferry',
        'position': pos++,
        'origin': origin,
        'destination': destination,
        if (date != null) 'depart_date': date,
        'passengers': 1,
      });
      ferryLegs[key] = (origin: origin, destination: destination, date: date);
    }

    // A leg between two Greek ports/islands (incl. Athens/Piraeus) is a ferry;
    // the long-haul home<->Greece legs stay flights.
    void addLeg(String origin, String destination, DateTime? when,
        {_Coord? originCoord, _Coord? destCoord}) {
      if (_isGreekIsland(origin) && _isGreekIsland(destination)) {
        addFerry(origin, destination, when);
      } else {
        addFlight(origin, destination, when,
            originCoord: originCoord, destCoord: destCoord);
      }
    }

    // Outbound: home airport -> first city, on the trip's start date.
    if (hasHome) {
      addFlight(home, ranges.first.label, ranges.first.start,
          destCoord: ranges.first.coord);
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
        addLeg(label, ranges[i + 1].label, r.end,
            originCoord: r.coord, destCoord: ranges[i + 1].coord);
      }
    }

    // Return: last city -> home airport, on the trip's end date.
    if (hasHome) {
      addFlight(ranges.last.label, home, ranges.last.end,
          originCoord: ranges.last.coord);
    }

    _flightLegs = legs;
    _ferryLegs = ferryLegs;
    return todos;
  }

  /// Partitions [_bookingTodos] into per-city embedded slots — the flight that
  /// arrives at the city, its stay, and (for the last city) the return flight
  /// home — plus the residual list of everything that matched no city
  /// (user-added `custom:*` todos, stale auto todos). Each todo is claimed at
  /// most once, so repeated city labels still render each booking exactly once.
  ({
    List<
        ({
          BookingTodo? arrival,
          BookingTodo? stay,
          BookingTodo? departure
        })> slots,
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
      arrivals.add(
          claim((t) => t.kind == 'transport' && t.todoKey.endsWith('>>$l')));
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
      residual: _bookingTodos.where((t) => !claimed.contains(t.id)).toList(),
    );
  }

  Future<void> _setBooked(BookingTodo todo, bool booked) async {
    if (_guardOffline()) return;
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
    if (_guardOffline()) return;
    try {
      await ref
          .read(bookingTodosApiServiceProvider)
          .delete(widget.tripId, todo.id);
      if (mounted) {
        setState(() => _bookingTodos =
            _bookingTodos.where((t) => t.id != todo.id).toList());
      }
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  Future<void> _addBooking() async {
    if (_guardOffline()) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddBookingTodoDialog(tripId: widget.tripId),
    );
    if (added == true) await _load();
  }

  /// [day] preselects the dialog's Day dropdown (e.g. from the map's
  /// empty-day CTA, where the user is already looking at a specific day).
  Future<void> _addPlace({int? day}) async {
    if (_guardOffline()) return;
    final trip = _trip;
    if (trip == null) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AddItineraryItemDialog(trip: trip, initialDay: day),
    );
    if (added == true) await _load();
  }

  Future<void> _patch(
      {String? title,
      String? startDate,
      String? endDate,
      String? status}) async {
    if (_guardOffline()) return;
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
    if (_guardOffline()) return;
    final controller = TextEditingController(text: _trip?.title ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit title'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
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
    if (_guardOffline()) return;
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
    // Chat/refine needs the network; also keeps the refine panel from ever
    // observing a cached (read-only) trip.
    if (_guardOffline()) return;
    // Owners and editor co-planners refine; viewer-role members are
    // read-only. Buttons are hidden, this is the belt-and-braces guard.
    if (!trip.canEdit) return;
    final items = trip.items ?? [];
    if (items.isEmpty) {
      _showSnack('Add some places before refining with AI.');
      return;
    }
    ref
        .read(tripRefineProvider(widget.tripId).notifier)
        .beginSectionRefinement(_buildSectionSeed(trip, target),
            displayLabel: target.assistant
                ? 'Trip assistant'
                : 'Refining ${target.label}');
    setState(() {
      _panelOpen = true;
      _refineTarget = target;
    });
  }

  /// FAB entry point: resumes the panel conversation if one is in progress,
  /// otherwise starts a fresh whole-trip assistant session.
  void _openChat(Trip trip) {
    if (_guardOffline()) return;
    // The FAB is hidden for read-only viewers; belt-and-braces like
    // _openRefine.
    if (!trip.canEdit) return;
    final hasConversation =
        ref.read(tripRefineProvider(widget.tripId)).messages.isNotEmpty;
    if (hasConversation) {
      setState(() {
        _panelOpen = true;
        // Restore a header if the screen was rebuilt and lost it; keep a
        // surviving section-refine target so its header stays accurate.
        _refineTarget ??= const RefineTarget.assistant();
      });
      return;
    }
    _openRefine(trip, const RefineTarget.assistant());
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
    final b =
        StringBuffer('I want to refine my saved trip "${_displayTitle(trip)}"');
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
        'places exactly as listed above (same coordinates and tags). ');
    b.write(t.assistant
        ? 'I may also just ask questions about the trip (flights, bookings, '
            'timing) — answer those directly without changing anything. '
            'Start by asking how you can help.'
        : 'Start by asking what I want to change.');
    return b.toString();
  }

  Future<void> _delete() async {
    if (_guardOffline()) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete trip?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(tripsProvider.notifier).deleteTrip(widget.tripId);
        await ref
            .read(recentTripProvider.notifier)
            .clearIfMatches(widget.tripId);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        _showSnack('Delete failed: $e');
      }
    }
  }

  void _showSnack(String msg) {
    if (mounted) showSnack(context, msg);
  }

  /// Drops this shared trip from the member's own list (the owner's trip is
  /// untouched). Editors and viewer follows alike.
  Future<void> _leaveTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from my trips?'),
        content: const Text(
            "You'll lose access until you're invited again. The trip itself "
            'is not deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(tripsApiServiceProvider).leaveTrip(widget.tripId);
      ref.invalidate(sharedWithMeProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Could not remove trip: $e');
    }
  }

  Future<void> _addStay() async {
    if (_guardOffline()) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddStaySheet(),
    );
    if (body == null) return;
    try {
      await ref
          .read(accommodationsApiServiceProvider)
          .add(widget.tripId, body);
      await _load();
    } catch (e) {
      _showSnack('Could not add stay: $e');
    }
  }

  Future<void> _deleteStay(Accommodation a) async {
    if (_guardOffline()) return;
    try {
      await ref
          .read(accommodationsApiServiceProvider)
          .delete(widget.tripId, a.id);
      await _load();
    } catch (e) {
      _showSnack('Could not remove stay: $e');
    }
  }

  /// Opens the stay sheet prefilled; a save PATCHes the row, which also
  /// confirms it if it was a Suggested draft.
  Future<void> _editStay(Accommodation a) async {
    if (_guardOffline()) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddStaySheet(initial: a),
    );
    if (body == null) return;
    try {
      await ref
          .read(accommodationsApiServiceProvider)
          .update(widget.tripId, a.id, body);
      await _load();
    } catch (e) {
      _showSnack('Could not update stay: $e');
    }
  }

  /// "Keep" on a Suggested draft: an empty PATCH confirms it as-is.
  Future<void> _confirmStay(Accommodation a) async {
    if (_guardOffline()) return;
    try {
      await ref
          .read(accommodationsApiServiceProvider)
          .update(widget.tripId, a.id, const {});
      await _load();
    } catch (e) {
      _showSnack('Could not keep stay: $e');
    }
  }

  Future<void> _addSegment() async {
    if (_guardOffline()) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddSegmentSheet(),
    );
    if (body == null) return;
    try {
      await ref
          .read(transportApiServiceProvider)
          .addSegment(widget.tripId, body);
      await _load();
    } catch (e) {
      _showSnack('Could not add transport: $e');
    }
  }

  Future<void> _deleteSegment(TripSegment s) async {
    if (_guardOffline()) return;
    try {
      await ref
          .read(transportApiServiceProvider)
          .deleteSegment(widget.tripId, s.id);
      await _load();
    } catch (e) {
      _showSnack('Could not remove transport: $e');
    }
  }

  /// Opens the transport sheet prefilled; a save PATCHes the row, which also
  /// confirms it if it was a Suggested draft.
  Future<void> _editSegment(TripSegment s) async {
    if (_guardOffline()) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddSegmentSheet(initial: s),
    );
    if (body == null) return;
    try {
      await ref
          .read(transportApiServiceProvider)
          .updateSegment(widget.tripId, s.id, body);
      await _load();
    } catch (e) {
      _showSnack('Could not update transport: $e');
    }
  }

  /// "Keep" on a Suggested draft: an empty PATCH confirms it as-is.
  Future<void> _confirmSegment(TripSegment s) async {
    if (_guardOffline()) return;
    try {
      await ref
          .read(transportApiServiceProvider)
          .updateSegment(widget.tripId, s.id, const {});
      await _load();
    } catch (e) {
      _showSnack('Could not keep transport: $e');
    }
  }

  /// Where the app is mounted on its host: '/' in dev, '/app/' in the
  /// Anchors the app-bar share menu so the iPad share popover has a rect to
  /// point at (share_plus requires sharePositionOrigin there).
  final GlobalKey _shareMenuKey = GlobalKey();

  Rect? _shareAnchorRect() {
    final box =
        _shareMenuKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// "Title · dates" line that accompanies a shared link.
  String _shareMessage(Trip trip) {
    final dates = tripDateRange(trip.startDate, trip.endDate);
    return dates == null
        ? _displayTitle(trip)
        : '${_displayTitle(trip)} · $dates';
  }

  /// Mints (or reuses) the trip's share link, then hands it to the OS share
  /// sheet (mobile) or the clipboard (web/desktop).
  Future<void> _shareLink() async {
    final trip = _trip;
    if (trip == null) return;
    try {
      final token = await ref
          .read(tripsApiServiceProvider)
          .createShareLink(widget.tripId);
      if (!mounted) return;
      await shareOrCopyLink(
        context,
        url: shareUrl(token),
        message: _shareMessage(trip),
        snackOnCopy: 'Share link copied to clipboard',
        sharePositionOrigin: _shareAnchorRect(),
      );
    } catch (e) {
      _showSnack('Could not create share link: $e');
    }
  }

  Future<void> _revokeLink() async {
    try {
      await ref.read(tripsApiServiceProvider).revokeShareLink(widget.tripId);
      _showSnack(
          'Sharing turned off — links no longer work (existing co-planners and followers keep access)');
    } catch (e) {
      _showSnack('Could not turn off sharing: $e');
    }
  }

  /// Mints an editor link and shares/copies it — the recipient can join as a
  /// co-planner and edit this trip.
  Future<void> _inviteCoPlanner() async {
    final trip = _trip;
    if (trip == null) return;
    try {
      final token = await ref
          .read(tripsApiServiceProvider)
          .createShareLink(widget.tripId, role: 'editor');
      if (!mounted) return;
      await shareOrCopyLink(
        context,
        url: shareUrl(token),
        message: 'Co-plan with me: ${_shareMessage(trip)}',
        snackOnCopy: 'Co-planner invite copied — anyone with it can edit',
        sharePositionOrigin: _shareAnchorRect(),
      );
    } catch (e) {
      _showSnack('Could not create invite: $e');
    }
  }

  /// Owner-only sheet listing active co-planners with per-person removal.
  Future<void> _manageCoPlanners() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _CoPlannersSheet(
        tripId: widget.tripId,
        onRemoved: () => _showSnack('Co-planner removed'),
        onInvited: (email) => _showSnack('Invite sent to $email'),
      ),
    );
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
    final parts = address
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first;
    final candidate = parts[parts.length - 2]; // segment before the country
    final tokens = candidate
        .split(RegExp(r'\s+'))
        .where((t) =>
            !RegExp(r'^[0-9][0-9\-]*$').hasMatch(t)) // drop postal tokens
        .toList();
    final city = tokens.join(' ').trim();
    return city.isEmpty ? candidate : city;
  }

  /// Groups items into consecutive runs sharing the same locality, labelling
  /// each run with the date range precomputed for that location (keyed by the
  /// first item's position).
  List<({String label, String? dateRange, List<ItineraryItem> items})>
      _buildGroups(
    List<ItineraryItem> items,
    Map<int, String> locationDates,
  ) {
    final groups =
        <({String label, String? dateRange, List<ItineraryItem> items})>[];
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

  /// Renders a hub group's items as slivers, split into "Day N" sub-sections
  /// when items carry day numbers (day-trip batching applied within each day).
  /// Each day is a [MultiSliver] whose header pins below the city header while
  /// the day's items scroll past, then is pushed off by the next day. Legacy
  /// items with no day fall back to flat day-trip batching with no day headers.
  List<Widget> _buildGroupItemSlivers(String cityKey, List<ItineraryItem> items,
      ThemeData theme, DateTime? tripStart,
      {required bool showTonight}) {
    if (!items.any((it) => it.day != null)) {
      return [_boxSliver(_buildDayTripWidgets(items, theme))];
    }
    // Today mode: the header for today's trip day (if any) gets a visible
    // highlight; undated/past/future trips resolve to null and render as-is.
    final todayDay =
        tripDayOn(_trip?.startDate, _trip?.endDate, DateTime.now());
    final slivers = <Widget>[];
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
        final header = _daySubHeader(
            day, tripStart, theme, collapsed, _runTravelMin(run), () {
          setState(() {
            if (collapsed) {
              _collapsedDays.remove(dayKey);
            } else {
              _collapsedDays.add(dayKey);
            }
          });
        },
            // Refine needs the network; owners and editor co-planners both
            // get the per-day refine icon (viewers don't).
            (!_isOffline && (_trip?.canEdit ?? true))
                ? () {
                    final trip = _trip;
                    if (trip == null) return;
                    // 'Other places' is a fallback label, not a real hub —
                    // omit the city qualifier so the server matches on the
                    // day alone.
                    _openRefine(
                        trip,
                        RefineTarget.day(day,
                            city: cityKey == 'Other places' ? null : cityKey));
                  }
                : null,
            headerKey: _dayHeaderKeys.putIfAbsent(dayKey, GlobalKey.new),
            isToday: day == todayDay);
        // Tonight caption (specs/happening-now): a non-pinned content row —
        // it scrolls and collapses with the section, never joining the
        // pinned chrome. [showTonight] is true for at most one group, so
        // repeated day numbers across city groups can't duplicate it.
        final trip = _trip;
        final tonight = (showTonight && day == todayDay && trip != null)
            ? _tonightCaption(theme, _staysOnNight(trip, day))
            : null;
        slivers.add(MultiSliver(
          pushPinnedChildren: true,
          children: [
            SliverPinnedHeader(child: header),
            if (!collapsed)
              _boxSliver([
                if (tonight != null) tonight,
                ..._buildDayTripWidgets(run, theme),
              ]),
          ],
        ));
      } else {
        slivers.add(_boxSliver(_buildDayTripWidgets(run, theme)));
      }
    }
    return slivers;
  }

  /// Wraps a run of box widgets as a single sliver for use inside MultiSliver.
  Widget _boxSliver(List<Widget> children) => SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  /// City group header: name, date range, refine + collapse controls. Pinned
  /// at the top of the scroll area while its group scrolls past; the opaque
  /// Material keeps items from showing through while pinned.
  Widget _cityHeader(
      Trip trip,
      ({String label, String? dateRange, List<ItineraryItem> items}) group,
      ThemeData theme) {
    final cityCollapsed = _collapsedCities.contains(group.label);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: InkWell(
        onTap: () => setState(() {
          if (cityCollapsed) {
            _collapsedCities.remove(group.label);
          } else {
            _collapsedCities.add(group.label);
          }
        }),
        child: Padding(
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
                  if (group.dateRange != null) ...[
                    Icon(Icons.event,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      group.dateRange!,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ],
                  // 'Other places' has no hub the section tool can target;
                  // refine also needs the network.
                  if (group.label != 'Other places' &&
                      trip.canEdit &&
                      !_isOffline)
                    IconButton(
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      tooltip: 'Refine ${group.label}',
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.primary,
                      onPressed: () =>
                          _openRefine(trip, RefineTarget.city(group.label)),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    cityCollapsed ? Icons.chevron_right : Icons.expand_more,
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
      ),
    );
  }

  /// Curated, locally-sourced recommendations for a city group — vetted picks
  /// from real locals. Renders nothing when there is no coverage for the city
  /// (empty list) or on error, so it never shows a broken/empty section.
  Widget _localIntelSliver(String label, ThemeData theme) {
    if (label == 'Other places') {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Consumer(builder: (context, ref, _) {
        final recs =
            ref.watch(localRecsByCityProvider(label)).valueOrNull ?? [];
        final guides =
            ref.watch(localGuidesByCityProvider(label)).valueOrNull ?? [];
        if (recs.isEmpty && guides.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  top: AppSpacing.sm, bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Icon(Icons.verified, size: 16, color: AppColors.toolLocal),
                  const SizedBox(width: 6),
                  Text(
                    'Local intel',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.toolLocal,
                    ),
                  ),
                ],
              ),
            ),
            for (final g in guides) _guideChip(g, theme),
            for (final r in recs.take(6))
              LocalRecCard(
                rec: r,
                onAddToTrip: () =>
                    _addToTrip(AddToTripPayload.fromLocalRec(r)),
              ),
          ],
        );
      }),
    );
  }

  /// A tappable "Local guide" row inside the Local intel section that opens the
  /// full narrative guide (story + ordered pins + map).
  Widget _guideChip(LocalGuide guide, ThemeData theme) {
    final accent = AppColors.toolLocal;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LocalGuideDetailScreen(guide: guide),
            )),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(Icons.menu_book, size: 20, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Local guide: ${guide.title}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (guide.sourceName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'By ${guide.sourceName}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: accent, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  /// Live local-events section for a city group, looked up for the group's date
  /// window. Returns an empty box (no sliver content) when the group has no
  /// real city/dates to query. Wrapped in a [Consumer] so only this section
  /// rebuilds as the async lookup resolves.
  Widget _eventsSliver(
    String label,
    ({DateTime? start, DateTime? end})? range,
    ThemeData theme,
  ) {
    if (label == 'Other places' ||
        range?.start == null ||
        range?.end == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final query = EventsQuery(
      city: label,
      startDate: _fmt(range!.start!),
      endDate: _fmt(range.end!),
    );
    return SliverToBoxAdapter(
      child: Consumer(builder: (context, ref, _) {
        final async = ref.watch(eventsByCityProvider(query));
        final header = Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
          child: Row(
            children: [
              Icon(Icons.local_activity, size: 16, color: AppColors.toolEvents),
              const SizedBox(width: 6),
              Text(
                'Events while you\'re here',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.toolEvents,
                ),
              ),
            ],
          ),
        );
        return async.when(
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('Finding events in $label…',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          // On error (e.g. provider key not set), try the Greek source-links
          // fallback rather than going silent.
          error: (_, __) => _greekEventsFallback(query, theme),
          data: (events) {
            if (events.isEmpty) return _greekEventsFallback(query, theme);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                for (final e in events.take(5))
                  EventCard(
                    event: e,
                    onAddToTrip: () =>
                        _addToTrip(AddToTripPayload.fromEvent(e)),
                  ),
              ],
            );
          },
        );
      }),
    );
  }

  /// When the structured events lookup is empty/errored, show curated Greek
  /// event-discovery links for Greek cities (empty for everywhere else, so this
  /// renders nothing). Keeps the section useful where Ticketmaster has no data.
  Widget _greekEventsFallback(EventsQuery query, ThemeData theme) {
    return Consumer(builder: (context, ref, _) {
      final links = ref.watch(greeceEventLinksProvider(query)).valueOrNull;
      if (links == null || links.isEmpty) return const SizedBox.shrink();
      return SourceLinksCard(
        icon: Icons.local_activity,
        accent: AppColors.toolEvents,
        title: 'Find events in ${query.city}',
        links: links,
      );
    });
  }

  /// Greek islands/ports we offer ferry connectors between (mirrors the API's
  /// isGreekLocation set; kept small and local since it only gates the UI hint).
  static const _greekIslands = {
    'athens', 'piraeus', 'santorini', 'thira', 'fira', 'oia', 'mykonos',
    'naxos', 'paros', 'ios', 'milos', 'syros', 'tinos', 'folegandros',
    'crete', 'heraklion', 'chania', 'rethymno', 'rhodes', 'kos', 'corfu',
    'kefalonia', 'zakynthos', 'lefkada', 'skiathos', 'skopelos', 'samos',
    'chios', 'lesbos', 'mytilene', 'karpathos', 'symi', 'hydra', 'spetses',
    'aegina',
  };

  bool _isGreekIsland(String label) {
    final n = label.toLowerCase().trim();
    if (n.contains('greece')) return true;
    if (_greekIslands.contains(n)) return true;
    final comma = n.indexOf(',');
    if (comma > 0 && _greekIslands.contains(n.substring(0, comma).trim())) {
      return true;
    }
    return false;
  }


  /// Compact booking rows for a city group's slot: arrival flight + stay when
  /// [departureOnly] is false, the return-home flight when true.
  List<Widget> _bookingRowWidgets(
    ({BookingTodo? arrival, BookingTodo? stay, BookingTodo? departure}) slot, {
    required bool departureOnly,
  }) {
    final todos = departureOnly ? [slot.departure] : [slot.arrival, slot.stay];
    return [
      for (final todo in todos)
        if (todo != null)
          BookingTodoRow(
            todo: todo,
            onBookedChanged: (v) => _setBooked(todo, v),
            onOpen: _openCallbackFor(todo),
            openLabelOverride: _ferryLegs.containsKey(todo.todoKey)
                ? 'Find ferries'
                : _flightLegs.containsKey(todo.todoKey)
                    ? 'Find flights'
                    : null,
          ),
    ];
  }

  /// Batches consecutive day-trip places (by town) under an indented
  /// "Day trip · <town>" sub-header so nearby towns read as excursions from the
  /// hub city rather than separate stops. Inserts a within-city travel-time
  /// connector between adjacent tiles of the same indent run.
  List<Widget> _buildDayTripWidgets(
      List<ItineraryItem> items, ThemeData theme) {
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
        widgets
            .add(_dayTripSubHeader(town, theme, _dayTripTravelLabel(items[i])));
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
  Widget? _travelConnector(ItineraryItem from, ItineraryItem to,
      double indentLeft, ThemeData theme) {
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
  /// when the trip start is known, otherwise falls back to "Day N". The opaque
  /// Material keeps items from showing through while the header is pinned —
  /// today's tint is alpha-blended onto the scaffold background (never a
  /// translucent color) for the same reason. [headerKey] gives the Today
  /// scroller a stable handle on the header's render box.
  Widget _daySubHeader(
      int day,
      DateTime? tripStart,
      ThemeData theme,
      bool collapsed,
      int travelMin,
      VoidCallback onTap,
      VoidCallback? onRefine,
      {Key? headerKey,
      bool isToday = false}) {
    final label = tripStart != null
        ? _fmtDayHeader(tripStart.add(Duration(days: day - 1)))
        : 'Day $day';
    final muted = theme.colorScheme.onSurfaceVariant;
    return Material(
      key: headerKey,
      color: isToday
          ? Color.alphaBlend(theme.colorScheme.primary.withValues(alpha: 0.06),
              theme.scaffoldBackgroundColor)
          : theme.scaffoldBackgroundColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
          child: Row(
            children: [
              Icon(Icons.today, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      StatusPill.custom(
                        label: 'Today',
                        background:
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                        foreground: theme.colorScheme.primary,
                      ),
                    ],
                  ],
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
              if (onRefine != null)
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
      ),
    );
  }

  /// "Tonight: <stay>" caption for today's day section (specs/happening-now
  /// PR 2): where the traveler sleeps tonight, checkout-exclusively. Returns
  /// null when no covering stay has a non-empty name — no filler row.
  Widget? _tonightCaption(ThemeData theme, List<Accommodation> stays) {
    final names = stays
        .map((a) => a.name.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    return Padding(
      // Matches the _dayTripSubHeader indent (20 left) so the caption reads
      // as a sub-row of the day, tucked tight under the header (6 top).
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 0),
      child: Row(
        children: [
          Icon(Icons.hotel, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Tonight: ${names.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayTripSubHeader(String town, ThemeData theme, String? travelLabel) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
        child: Row(
          children: [
            Icon(Icons.directions_bus,
                size: 16, color: theme.colorScheme.secondary),
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
              Icon(Icons.directions_car_outlined,
                  size: 14, color: theme.colorScheme.onSurfaceVariant),
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

  /// Opens the add-to-trip picker for a browsed place (local rec / event) with
  /// this trip preselected, then refreshes in place when the add landed here.
  Future<void> _addToTrip(AddToTripPayload payload) async {
    final added =
        await showAddToTripSheet(context, payload, currentTripId: widget.tripId);
    // _refresh(), not a bare silent _load(): it serializes with any reload the
    // refine panel has in flight, so a pre-add snapshot can't land after us
    // and momentarily erase the just-added item.
    if (added != null && added.id == widget.tripId) _refresh();
  }

  Widget _itemTile(ItineraryItem item, double indentLeft, ThemeData theme) =>
      Padding(
        padding: EdgeInsets.only(left: indentLeft),
        child: ListTile(
          leading: _itemLeading(item.category, item.position),
          title: Text(item.name),
          subtitle: (item.address != null || item.localSourceName != null)
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.address != null) Text(item.address!),
                    // The local-source credit line: who vouched for this place
                    // (snapshot; shown for agent- and browse-added items alike).
                    if (item.localSourceName != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified,
                              size: 13, color: AppColors.toolLocal),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Recommended by ${item.localSourceName}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.toolLocal,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                  ],
                )
              : null,
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
              if (!_readOnly) _itemMenu(item),
            ],
          ),
          selected: _selectedPosition == item.position,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          // The map is pinned and always on screen, so tapping an item only
          // needs to update the selection; TripMap recenters on the new pin.
          onTap: () => setState(() => _selectedPosition = item.position),
        ),
      );

  /// Per-item actions: edit, move within its section, delete (with undo).
  /// Move targets the neighbor in itinerary order but only within the same
  /// day + hub + day-trip batch, so an item can never silently jump across a
  /// section boundary — cross-day moves go through the edit sheet instead.
  Widget _itemMenu(ItineraryItem item) {
    final canUp = _moveNeighbor(item, -1) != null;
    final canDown = _moveNeighbor(item, 1) != null;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Place actions',
      onSelected: (action) {
        switch (action) {
          case 'edit':
            _editItem(item);
          case 'up':
            _moveItem(item, -1);
          case 'down':
            _moveItem(item, 1);
          case 'reorder':
            _reorderSection(item);
          case 'delete':
            _deleteItem(item);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canUp)
          const PopupMenuItem(
            value: 'up',
            child: ListTile(
              leading: Icon(Icons.arrow_upward),
              title: Text('Move up'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDown)
          const PopupMenuItem(
            value: 'down',
            child: ListTile(
              leading: Icon(Icons.arrow_downward),
              title: Text('Move down'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (_sectionOf(item).length > 2)
          const PopupMenuItem(
            value: 'reorder',
            child: ListTile(
              leading: Icon(Icons.drag_indicator),
              title: Text('Reorder section'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Remove'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  /// The item this one would swap with when moved by [delta] (-1 up, +1 down),
  /// or null when the move would cross a day/hub/day-trip boundary.
  ItineraryItem? _moveNeighbor(ItineraryItem item, int delta) {
    final items = _trip?.items;
    if (items == null) return null;
    final idx = items.indexWhere((i) => i.id == item.id);
    if (idx < 0) return null;
    final ni = idx + delta;
    if (ni < 0 || ni >= items.length) return null;
    final other = items[ni];
    if (other.day != item.day) return null;
    if (_hubOf(other) != _hubOf(item)) return null;
    if ((other.dayTripFrom ?? '').trim() != (item.dayTripFrom ?? '').trim()) {
      return null;
    }
    return other;
  }

  /// All items sharing [item]'s day + hub + day-trip batch, in itinerary
  /// order — the same boundary _moveNeighbor enforces, so drag reordering
  /// can never move an item across a section either.
  List<ItineraryItem> _sectionOf(ItineraryItem item) {
    final items = _trip?.items ?? const <ItineraryItem>[];
    return [
      for (final i in items)
        if (i.day == item.day &&
            _hubOf(i) == _hubOf(item) &&
            (i.dayTripFrom ?? '').trim() == (item.dayTripFrom ?? '').trim())
          i,
    ];
  }

  /// Drag-and-drop reorder for one section (specs/itinerary-item-editing
  /// follow-up). The sheet reorders locally; Save maps the section's new
  /// order back onto the full item-id permutation and submits it through the
  /// same PUT /items/order path as Move up/down.
  Future<void> _reorderSection(ItineraryItem item) async {
    if (_guardOffline()) return;
    final trip = _trip;
    if (trip == null) return;
    final section = _sectionOf(item);
    if (section.length < 2) return;

    final newOrder = await showModalBottomSheet<List<ItineraryItem>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ReorderSectionSheet(items: section),
    );
    if (newOrder == null || !mounted) return;

    // Splice the section's new order into the full ordering: walk the trip's
    // items and replace each section member slot with the next reordered id.
    final sectionIds = section.map((i) => i.id).toSet();
    var next = 0;
    final ids = <String>[
      for (final i in trip.items ?? const <ItineraryItem>[])
        if (sectionIds.contains(i.id)) newOrder[next++].id else i.id,
    ];
    try {
      await ref
          .read(tripsApiServiceProvider)
          .reorderItineraryItems(trip.id, ids);
      await _load();
    } catch (e) {
      _showSnack('Could not reorder: $e');
      await _load();
    }
  }

  Future<void> _moveItem(ItineraryItem item, int delta) async {
    if (_guardOffline()) return;
    final trip = _trip;
    final other = _moveNeighbor(item, delta);
    if (trip == null || other == null) return;
    final ids = (trip.items ?? const <ItineraryItem>[])
        .map((i) => i.id)
        .toList();
    final a = ids.indexOf(item.id);
    final b = ids.indexOf(other.id);
    ids[a] = other.id;
    ids[b] = item.id;
    try {
      await ref
          .read(tripsApiServiceProvider)
          .reorderItineraryItems(trip.id, ids);
      await _load();
    } catch (e) {
      _showSnack('Could not reorder: $e');
      await _load();
    }
  }

  Future<void> _deleteItem(ItineraryItem item) async {
    if (_guardOffline()) return;
    final trip = _trip;
    if (trip == null) return;
    try {
      await ref
          .read(tripsApiServiceProvider)
          .deleteItineraryItem(trip.id, item.id);
    } catch (e) {
      _showSnack('Could not remove ${item.name}: $e');
      return;
    }
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${item.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoDelete(trip.id, item),
        ),
      ),
    );
  }

  /// Undo = re-add through the normal add endpoint; the server slots the item
  /// back at the end of its day, which is close enough to where it was.
  Future<void> _undoDelete(String tripId, ItineraryItem item) async {
    final body = <String, dynamic>{
      'name': item.name,
      if (item.placeId != null) 'place_id': item.placeId,
      if (item.address != null) 'address': item.address,
      if (item.latitude != 0 || item.longitude != 0) ...{
        'latitude': item.latitude,
        'longitude': item.longitude,
      },
      if (item.category != null) 'category': item.category,
      if (item.timeOfDay != null) 'time_of_day': item.timeOfDay,
      if (item.city != null) 'city': item.city,
      if (item.dayTripFrom != null) 'day_trip_from': item.dayTripFrom,
      if (item.day != null) 'day': item.day,
    };
    try {
      await ref.read(tripsApiServiceProvider).addItineraryItem(tripId, body);
      await _load();
    } catch (e) {
      _showSnack('Could not restore ${item.name}: $e');
    }
  }

  Future<void> _editItem(ItineraryItem item) async {
    if (_guardOffline()) return;
    final changes = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditItineraryItemSheet(item: item),
    );
    if (changes == null || changes.isEmpty) return;
    final trip = _trip;
    if (trip == null) return;
    try {
      await ref
          .read(tripsApiServiceProvider)
          .updateItineraryItem(trip.id, item.id, changes);
      await _load();
    } catch (e) {
      _showSnack('Could not update ${item.name}: $e');
    }
  }

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
  List<({String label, DateTime? start, DateTime? end, _Coord? coord})>
      _locationGroupRanges(Trip trip) {
    final items = trip.items ?? const <ItineraryItem>[];
    if (items.isEmpty) return const [];
    // Confirmed only: a suggested draft's dates come FROM this derivation, so
    // letting them back in via _accDateRangeFor would freeze the ranges.
    final stays = _confirmedStays(trip);

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
    final auto =
        List<({DateTime start, DateTime end})?>.filled(groups.length, null);
    if (start != null && end != null && !end.isBefore(start)) {
      final totalDays = end.difference(start).inDays + 1;
      final n = groups.length;
      if (n <= totalDays) {
        // Enough days: give each location a contiguous slice weighted by size.
        final counts =
            _allocateDays(totalDays, [for (final g in groups) g.length]);
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
          final d = start.add(
              Duration(days: (i * totalDays ~/ n).clamp(0, totalDays - 1)));
          auto[i] = (start: d, end: d);
        }
      }
    }

    final result =
        <({String label, DateTime? start, DateTime? end, _Coord? coord})>[];
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
        coord: _groupCoord(g),
      ));
    }
    return result;
  }

  /// A representative coordinate for a location group: the first item with real
  /// coordinates. (0,0) is the "no location" sentinel for manually-added places.
  _Coord? _groupCoord(List<ItineraryItem> group) {
    for (final it in group) {
      if (it.latitude != 0 || it.longitude != 0) {
        return (lat: it.latitude, lng: it.longitude);
      }
    }
    return null;
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
    if (totalDays <= n) {
      return List.filled(n, 1); // ranges clamp to the trip end
    }
    final totalW = weights.fold<int>(0, (s, w) => s + (w <= 0 ? 1 : w));
    final exact = [
      for (final w in weights) totalDays * (w <= 0 ? 1 : w) / totalW
    ];
    final counts = [for (final e in exact) e.floor() < 1 ? 1 : e.floor()];
    var used = counts.fold<int>(0, (s, c) => s + c);
    // Hand out any remaining days to the largest fractional remainders.
    final byRemainder = List<int>.generate(n, (i) => i)
      ..sort((a, b) =>
          (exact[b] - exact[b].floor()).compareTo(exact[a] - exact[a].floor()));
    for (var k = 0; used < totalDays; k++) {
      counts[byRemainder[k % n]] += 1;
      used++;
    }
    // Or trim back from the largest groups if min-1 overshot.
    final byCount = List<int>.generate(n, (i) => i)
      ..sort((a, b) => counts[b].compareTo(counts[a]));
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

  /// Coarse relative timestamp for the "Updated by X" line.
  String _relativeTime(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return 'recently';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  /// Day-header date, e.g. "Tue, Jul 15" (weekday + month + day).
  String _fmtDayHeader(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
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
                if (trip.canEdit)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'Rename',
                    onPressed: _isOffline ? null : _editTitle,
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
                  onPressed:
                      (_isOffline || !trip.canEdit) ? null : _editDates,
                ),
                if (trip.canEdit)
                  PopupMenuButton<String>(
                    tooltip: 'Change status',
                    enabled: !_isOffline,
                    onSelected: (v) => _patch(status: v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'draft', child: Text('Draft')),
                      PopupMenuItem(value: 'planned', child: Text('Planned')),
                    ],
                    child: StatusPill(
                      status: trip.status,
                      trailing: const Icon(Icons.arrow_drop_down),
                    ),
                  )
                else
                  StatusPill(status: trip.status),
              ],
            ),
            const SizedBox(height: 12),
            if (!trip.isOwner) ...[
              Row(
                children: [
                  Icon(
                      trip.canEdit
                          ? Icons.group_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trip.canEdit
                          ? (trip.ownerName != null
                              ? 'Co-planning with ${trip.ownerName} — your changes save for everyone.'
                              : 'Co-planning a shared trip — your changes save for everyone.')
                          : (trip.ownerName != null
                              ? 'Shared by ${trip.ownerName} — view only.'
                              : 'Shared trip — view only.'),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (trip.canEdit)
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  // Chat/refine needs the network — disabled while offline.
                  onPressed: _isOffline
                      ? null
                      : () => _openRefine(trip, const RefineTarget.trip()),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Refine with AI'),
                ),
              ),
            // "Updated by Maria · 2m ago" — only present when someone ELSE
            // made the last edit (the server omits self-attribution).
            if (trip.updatedByName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Updated by ${trip.updatedByName} · ${_relativeTime(trip.updatedAt)}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
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
      // Always-reachable chat entry, mirroring the _openRefine guards so it's
      // never a dead button. Hidden while the panel is open: on wide layouts
      // the panel is docked (redundant), on narrow it would overlap the sheet.
      floatingActionButton: (trip != null &&
              !_panelOpen &&
              trip.canEdit &&
              !_isOffline &&
              (trip.items?.isNotEmpty ?? false))
          ? FloatingActionButton(
              tooltip: 'Ask AI about this trip',
              onPressed: () => _openChat(trip),
              child: const Icon(Icons.chat_bubble_outline),
            )
          : null,
      appBar: GradientAppBar(
        title: Text(trip != null ? _displayTitle(trip) : 'Trip'),
        actions: [
          // Sharing and deletion are owner-only surfaces; editors see
          // neither. Both mutate, so they're hidden while offline-serving.
          if (trip != null && trip.isOwner && !_isOffline)
            PopupMenuButton<String>(
              key: _shareMenuKey,
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share trip',
              onSelected: (v) => switch (v) {
                'copy' => _shareLink(),
                'invite' => _inviteCoPlanner(),
                'manage' => _manageCoPlanners(),
                _ => _revokeLink(),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: 'copy',
                    child: Text(shareUsesNativeSheet
                        ? 'Share link…'
                        : 'Copy share link')),
                PopupMenuItem(
                    value: 'invite',
                    child: Text(shareUsesNativeSheet
                        ? 'Share co-planner invite…'
                        : 'Copy invite link (can edit)')),
                const PopupMenuItem(
                    value: 'manage', child: Text('Manage access')),
                const PopupMenuItem(
                    value: 'revoke', child: Text('Turn off sharing')),
              ],
            ),
          if (trip != null && trip.isOwner && !_isOffline)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete trip',
              onPressed: _delete,
            ),
          // Members (editors and viewer follows) can drop the trip from
          // their own list; the owner's trip is untouched.
          if (trip != null && !trip.isOwner && !_isOffline)
            IconButton(
              icon: const Icon(Icons.bookmark_remove_outlined),
              tooltip: 'Remove from my trips',
              onPressed: _leaveTrip,
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
                      FilledButton(
                          onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : trip == null
                  ? const SizedBox.shrink()
                  : LayoutBuilder(builder: (context, constraints) {
                      // City-matched bookings render inside their city group;
                      // the rest fall through to the "Other bookings" section.
                      final grouped = _groupedBookings([
                        for (final r in _locationGroupRanges(trip)) r.label
                      ]);
                      final filtered = _filtered(trip);
                      final groups =
                          _buildGroups(filtered, _locationDates(trip));
                      // Date window per city group, for the embedded events
                      // lookup (keyed by the same label _buildGroups uses).
                      final groupRanges = {
                        for (final r in _locationGroupRanges(trip))
                          r.label: (start: r.start, end: r.end)
                      };
                      final tripStart = DateTime.tryParse(trip.startDate ?? '');
                      // Map day chips (specs/today-mode). Day count spans the
                      // whole trip, not the category filter, so chips never
                      // come and go with the Attractions/Restaurants toggle.
                      final mapDayCount = dayCount(
                        trip.startDate,
                        trip.endDate,
                        (trip.items ?? const <ItineraryItem>[])
                            .map((i) => i.day),
                      );
                      // A refresh can shrink the trip below a stale selection
                      // (fewer days after an edit); fall back to All. Plain
                      // assignment: we're already in build, so this frame
                      // renders the clamped value.
                      if (_selectedDay != null && _selectedDay! > mapDayCount) {
                        _selectedDay = null;
                      }
                      // Days that would plot something, so empty days (e.g.
                      // the fly-out day, all booking todos) get muted chips.
                      // Trip-wide like mapDayCount — the category filter never
                      // flickers the chip treatment.
                      final mappedDays = daysWithMappedContent(
                        trip.startDate,
                        mapDayCount,
                        [
                          for (final i
                              in trip.items ?? const <ItineraryItem>[])
                            if (i.latitude != 0 || i.longitude != 0) i.day,
                        ],
                        [
                          for (final a in _confirmedStays(trip))
                            if (TripMap.stayHasCoords(a))
                              (checkIn: a.checkIn, checkOut: a.checkOut),
                        ],
                      );
                      // Today mode: the jump chip renders only when today
                      // falls inside the trip's dates AND some item carries a
                      // day tag (the same gate as the auto-scroll, so the
                      // chip never points at nothing).
                      final todayDay =
                          tripDayOn(trip.startDate, trip.endDate, DateTime.now());
                      final hasTodayTarget = todayDay != null &&
                          (trip.items ?? const <ItineraryItem>[])
                              .any((i) => i.day != null);
                      // Tonight caption (specs/happening-now): day numbers
                      // repeat across city groups (keys are '$cityKey#$day'),
                      // so resolve the FIRST group containing today's day
                      // once, here — exactly one caption can ever render.
                      String? firstTodayGroupLabel;
                      if (todayDay != null) {
                        for (final group in groups) {
                          if (group.items.any((it) => it.day == todayDay)) {
                            firstTodayGroupLabel = group.label;
                            break;
                          }
                        }
                      }
                      // A loud load queued the one-shot auto-scroll; this is
                      // the first frame that actually mounts the scroll view
                      // (and registers the day-header keys), so kick it off
                      // once this frame's layout is done.
                      final pendingToday = _pendingTodayScroll;
                      if (pendingToday != null) {
                        _pendingTodayScroll = null;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _scrollToDay(pendingToday);
                        });
                      }
                      final scrollView = CustomScrollView(
                        controller: _scroll,
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
                          if (_mapShown(trip))
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _PinnedHeaderDelegate(
                                height: _mapHeaderHeight,
                                backgroundColor: theme.scaffoldBackgroundColor,
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                child: ClipRRect(
                                  borderRadius: AppRadius.lgAll,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: TripMap(
                                          items: _dayFiltered(trip),
                                          accommodations:
                                              _dayFilteredStays(trip),
                                          selectedPosition: _selectedPosition,
                                          // Unfiltered by day: TripMap's
                                          // position+1 adjacency guard drops
                                          // labels across the gaps a day
                                          // filter creates, and the category
                                          // filter already empties this map.
                                          segmentLabels: _segmentLabels(),
                                          fitSignature: _selectedDay,
                                          // Keep fitted markers clear of the
                                          // chip row overlaid below.
                                          topOverlayInset: mapDayCount > 0
                                              ? MapDayChips.mapTopInset
                                              : 0,
                                          emptyLabel: _selectedDay == null
                                              ? 'No mapped places'
                                              : 'No places pinned on '
                                                  'Day $_selectedDay',
                                          emptyMessage: _isOffline
                                              ? null
                                              : 'Add a place to see it '
                                                  'on the map.',
                                          emptyAction: (_isOffline ||
                                                  _readOnly)
                                              ? null
                                              : FilledButton.tonalIcon(
                                                  onPressed: () => _addPlace(
                                                      day: _selectedDay),
                                                  icon: const Icon(Icons.add,
                                                      size: 18),
                                                  label:
                                                      const Text('Add place'),
                                                ),
                                          onPinTap: (pos) {
                                            setState(
                                                () => _selectedPosition = pos);
                                            final it = trip.items!.firstWhere(
                                                (i) => i.position == pos);
                                            _showSnack(it.name);
                                          },
                                        ),
                                      ),
                                      // Above the map's gesture layer, so
                                      // chip taps and row scrolls never pan
                                      // the map.
                                      Positioned(
                                        top: 8,
                                        left: 8,
                                        right: 8,
                                        child: MapDayChips(
                                          dayCount: mapDayCount,
                                          selected: _selectedDay,
                                          mappedDays: mappedDays,
                                          onSelected: (d) => setState(
                                              () => _selectedDay = d),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          // Itinerary title + category filter; pins beneath the
                          // map so the filter stays reachable while scrolling.
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _PinnedHeaderDelegate(
                              // title row + filter chip row; title-row-only
                              // when there are no items (see the constants).
                              height: (trip.items ?? const []).isNotEmpty
                                  ? _listHeaderHeight
                                  : _listHeaderHeightEmpty,
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
                                                style: theme
                                                    .textTheme.titleMedium),
                                          ),
                                          if (hasTodayTarget) ...[
                                            ActionChip(
                                              avatar: Icon(Icons.today,
                                                  size: 16,
                                                  color: theme
                                                      .colorScheme.primary),
                                              label: const Text('Today'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              // Pure view work (select +
                                              // expand + scroll): allowed
                                              // offline and while the refine
                                              // panel is open.
                                              onPressed: () {
                                                setState(() =>
                                                    _selectedDay = todayDay);
                                                _scrollToDay(todayDay);
                                              },
                                            ),
                                            const SizedBox(width: 4),
                                          ],
                                          if (!_readOnly)
                                            TextButton.icon(
                                              onPressed: _isOffline
                                                  ? null
                                                  : _addPlace,
                                              style: TextButton.styleFrom(
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                              icon: const Icon(Icons.add,
                                                  size: 18),
                                              label: const Text('Add place'),
                                            ),
                                        ],
                                      ),
                                    ),
                                    if ((trip.items ?? const [])
                                        .isNotEmpty) ...[
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
                          if ((trip.items ?? []).isEmpty)
                            const SliverToBoxAdapter(
                              child: SizedBox(
                                height: 260,
                                child: EmptyState(
                                  icon: Icons.place_outlined,
                                  title: 'No places yet',
                                  message:
                                      'Refine with AI or add a place to start your itinerary.',
                                ),
                              ),
                            )
                          else if (filtered.isEmpty)
                            SliverToBoxAdapter(
                              child: _FilterMissNotice(theme: theme),
                            )
                          else
                            // Each city is a MultiSliver whose header pins
                            // beneath the filter bar while the city's items
                            // scroll past, then is pushed off by the next city;
                            // day headers nest the same way within each city.
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                              sliver: MultiSliver(children: [
                                for (final (gi, group) in groups.indexed)
                                  MultiSliver(
                                    pushPinnedChildren: true,
                                    children: [
                                      SliverPinnedHeader(
                                          child: KeyedSubtree(
                                              key: _cityHeaderKeys.putIfAbsent(
                                                  group.label, GlobalKey.new),
                                              child: _cityHeader(
                                                  trip, group, theme))),
                                      if (!_collapsedCities
                                          .contains(group.label)) ...[
                                        // Embedded bookings render only in the
                                        // unfiltered view: a category filter can
                                        // merge adjacent same-label runs, which
                                        // would break the slot<->group mapping.
                                        if (_itemFilter == 'all' &&
                                            gi < grouped.slots.length)
                                          _boxSliver(_bookingRowWidgets(
                                              grouped.slots[gi],
                                              departureOnly: false)),
                                        ..._buildGroupItemSlivers(
                                            group.label,
                                            group.items,
                                            theme,
                                            tripStart,
                                            showTonight: group.label ==
                                                firstTodayGroupLabel),
                                        // Curated local recommendations for this
                                        // city — the "legit info you can't
                                        // google" surface. Leads the events
                                        // section; only in the unfiltered view.
                                        if (_itemFilter == 'all')
                                          _localIntelSliver(group.label, theme),
                                        // Local events for this city's dates —
                                        // only in the unfiltered view, where
                                        // group labels map 1:1 to date ranges.
                                        if (_itemFilter == 'all')
                                          _eventsSliver(
                                              group.label,
                                              groupRanges[group.label],
                                              theme),
                                        if (_itemFilter == 'all' &&
                                            gi == groups.length - 1 &&
                                            gi < grouped.slots.length)
                                          _boxSliver(_bookingRowWidgets(
                                              grouped.slots[gi],
                                              departureOnly: true)),
                                      ],
                                    ],
                                  ),
                              ]),
                            ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Divider(height: 32),
                                  // Saved stays & transport: what the user has
                                  // actually booked, distinct from the derived
                                  // checklist above — plus Suggested drafts
                                  // seeded from the itinerary by the sync.
                                  BookingsSection(
                                    trip: trip,
                                    stays: _stays,
                                    segments: _segments,
                                    readOnly: _readOnly,
                                    onAddStay: _addStay,
                                    onDeleteStay: _deleteStay,
                                    onEditStay: _editStay,
                                    onConfirmStay: _confirmStay,
                                    onAddSegment: _addSegment,
                                    onDeleteSegment: _deleteSegment,
                                    onEditSegment: _editSegment,
                                    onConfirmSegment: _confirmSegment,
                                  ),
                                  // Bookings live embedded in their city groups;
                                  // this section appears only when something
                                  // didn't match a city (custom or stale todos).
                                  // Viewers get no checklist at all (the server
                                  // withholds todos from them).
                                  if (grouped.residual.isEmpty && !_readOnly)
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton.icon(
                                        onPressed: _isOffline ? null : _addBooking,
                                        icon: const Icon(Icons.add, size: 18),
                                        label: const Text('Add booking'),
                                      ),
                                    )
                                  else ...[
                                    const Divider(height: 32),
                                    Row(
                                      children: [
                                        Expanded(
                                            child: Text('Other bookings',
                                                style: theme
                                                    .textTheme.titleMedium)),
                                        TextButton.icon(
                                          onPressed: _isOffline ? null : _addBooking,
                                          icon: const Icon(Icons.add, size: 18),
                                          label: const Text('Add'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    for (final todo in grouped.residual)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: BookingTodoCard(
                                          todo: todo,
                                          onBookedChanged: (v) =>
                                              _setBooked(todo, v),
                                          onOpen: _openCallbackFor(todo),
                                          openLabelOverride: _flightLegs
                                                  .containsKey(todo.todoKey)
                                              ? 'Find flights'
                                              : null,
                                          onDelete: todo.auto
                                              ? null
                                              : () => _deleteTodo(todo),
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      );

                      // Pull-to-refresh: with async co-editing, this is how a
                      // user picks up a collaborator's latest changes.
                      Widget refreshable = RefreshIndicator(
                        onRefresh: _refresh,
                        child: scrollView,
                      );
                      // Offline: the trip on screen is a cached copy — pin
                      // the banner above it. Retry takes the loud load path,
                      // which exits offline mode on success or re-serves the
                      // copy on another network failure.
                      final offlineSince = _offlineSince;
                      if (offlineSince != null) {
                        refreshable = Column(
                          children: [
                            OfflineBanner(
                                savedAt: offlineSince, onRetry: _load),
                            Expanded(child: refreshable),
                          ],
                        );
                      }

                      if (!_panelOpen || _refineTarget == null) {
                        return refreshable;
                      }
                      final panel = TripRefinePanel(
                        tripId: widget.tripId,
                        target: _refineTarget!,
                        onClose: () => setState(() => _panelOpen = false),
                        onTripUpdated: _refresh,
                      );
                      if (constraints.maxWidth >= 900) {
                        // Wide: dock the chat beside the itinerary.
                        return Row(
                          children: [
                            Expanded(child: refreshable),
                            const VerticalDivider(width: 1),
                            SizedBox(width: 400, child: panel),
                          ],
                        );
                      }
                      // Narrow: collapsible bottom sheet over the page; bottom
                      // inset keeps the input above the keyboard.
                      return Stack(
                        children: [
                          refreshable,
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
                                    bottom: MediaQuery.of(context)
                                        .viewInsets
                                        .bottom),
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
                                            color: theme
                                                .colorScheme.outlineVariant,
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
    // The attach-rate numerator (specs/instrumentation-events): opening any
    // booking handoff counts as a click. External links record-then-launch via
    // trackedLaunchUrl; the one in-app handoff (Find Flights) records via the
    // same helper before navigating. Fire-and-forget either way.
    if (todo.kind == 'transport') {
      final ferry = _ferryLegs[todo.todoKey];
      if (ferry != null) {
        return () => _openFerry(ferry, todo);
      }
      final leg = _flightLegs[todo.todoKey];
      if (leg != null) {
        return () {
          trackBookingLinkClick(
            context,
            provider: 'duffel',
            surface: 'booking_checklist',
            tripId: widget.tripId,
            todoKey: todo.todoKey,
            kind: todo.kind,
          );
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => FlightSearchScreen(
              prefillOrigin: leg.origin,
              prefillDestination: leg.destination,
              prefillDepartDate: leg.date,
              prefillOriginCoord: leg.originCoord,
              prefillDestinationCoord: leg.destCoord,
            ),
          ));
        };
      }
    }
    if (todo.searchUrl != null) {
      return () async {
        final ok = await trackedLaunchUrl(
          context,
          todo.searchUrl!,
          provider: (todo.provider ?? 'unknown').toLowerCase(),
          surface: 'booking_checklist',
          tripId: widget.tripId,
          todoKey: todo.todoKey,
          kind: todo.kind,
        );
        if (!ok) _showSnack('Could not open link');
      };
    }
    return null;
  }

  /// Opens the Ferryhopper search for a ferry leg. The booking URL (with the
  /// correct port codes) is built server-side, so we fetch it on tap — a single
  /// quick GET — keeping the port-code map a single source of truth in the API.
  Future<void> _openFerry(
      ({String origin, String destination, String? date}) leg,
      BookingTodo todo) async {
    try {
      final options = await ref.read(ferryApiServiceProvider).searchFerries(
            leg.origin,
            leg.destination,
            date: leg.date,
          );
      if (!mounted) return;
      if (options.isNotEmpty && options.first.bookingUrl.isNotEmpty) {
        final ok = await trackedLaunchUrl(
          context,
          options.first.bookingUrl,
          provider: 'ferryhopper',
          surface: 'booking_checklist',
          tripId: widget.tripId,
          todoKey: todo.todoKey,
          kind: todo.kind,
        );
        if (!ok) _showSnack('Could not open link');
        return;
      }
    } catch (_) {
      // fall through to the generic failure snack
    }
    _showSnack('Could not open ferry search');
  }

  // Raw launcher for non-booking links only (the per-item "Open in Google
  // Maps" action) — booking handoffs must go through trackedLaunchUrl.
  Future<void> _launch(String url) async {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
        if (_nn(_destination.text) != null)
          'destination': _nn(_destination.text),
        if (isTransport && _nn(_origin.text) != null)
          'origin': _nn(_origin.text),
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

/// Compact, centered notice shown when a category filter hides every item — a
/// lighter touch than the full empty state since the fix (clearing the filter)
/// is right above it.
class _FilterMissNotice extends StatelessWidget {
  final ThemeData theme;
  const _FilterMissNotice({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No places match this filter.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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

/// Bottom sheet for editing one itinerary item. Returns a map of only the
/// changed fields (the PATCH endpoint is a partial update), or null/empty on
/// cancel or no changes.
class _EditItineraryItemSheet extends StatefulWidget {
  final ItineraryItem item;
  const _EditItineraryItemSheet({required this.item});

  @override
  State<_EditItineraryItemSheet> createState() =>
      _EditItineraryItemSheetState();
}

class _EditItineraryItemSheetState extends State<_EditItineraryItemSheet> {
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _day;
  String? _category;
  String? _timeOfDay;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.name);
    _city = TextEditingController(text: widget.item.city ?? '');
    _day = TextEditingController(text: widget.item.day?.toString() ?? '');
    _category = widget.item.category;
    _timeOfDay = widget.item.timeOfDay;
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _day.dispose();
    super.dispose();
  }

  void _save() {
    final changes = <String, dynamic>{};
    final name = _name.text.trim();
    if (name.isNotEmpty && name != widget.item.name) changes['name'] = name;
    final city = _city.text.trim();
    if (city.isNotEmpty && city != (widget.item.city ?? '')) {
      changes['city'] = city;
    }
    final day = int.tryParse(_day.text.trim());
    if (day != null && day >= 1 && day != widget.item.day) {
      changes['day'] = day;
    }
    if (_category != null && _category != widget.item.category) {
      changes['category'] = _category;
    }
    if (_timeOfDay != null && _timeOfDay != widget.item.timeOfDay) {
      changes['time_of_day'] = _timeOfDay;
    }
    Navigator.of(context).pop(changes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit place', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _city,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _day,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Day',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            children: [
              for (final c in const [
                ('attraction', 'Attraction'),
                ('restaurant', 'Restaurant'),
              ])
                ChoiceChip(
                  label: Text(c.$2),
                  selected: _category == c.$1,
                  onSelected: (sel) =>
                      setState(() => _category = sel ? c.$1 : _category),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            children: [
              for (final t in const [
                ('morning', 'Morning'),
                ('afternoon', 'Afternoon'),
                ('evening', 'Evening'),
              ])
                ChoiceChip(
                  label: Text(t.$2),
                  selected: _timeOfDay == t.$1,
                  onSelected: (sel) =>
                      setState(() => _timeOfDay = sel ? t.$1 : _timeOfDay),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Owner-only bottom sheet: lists active co-planners with per-person removal.
/// Removal revokes their access immediately; the invite link (if still on)
/// would let them rejoin, so the empty state reminds the owner of that.
class _CoPlannersSheet extends ConsumerStatefulWidget {
  final String tripId;
  final VoidCallback onRemoved;
  final void Function(String email) onInvited;
  const _CoPlannersSheet(
      {required this.tripId, required this.onRemoved, required this.onInvited});

  @override
  ConsumerState<_CoPlannersSheet> createState() => _CoPlannersSheetState();
}

class _CoPlannersSheetState extends ConsumerState<_CoPlannersSheet> {
  List<({String userId, String displayName, String email, String role})>?
      _collaborators;
  List<({String id, String email, DateTime expiresAt})>? _invites;
  final _emailController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final service = ref.read(tripsApiServiceProvider);
      final results = await Future.wait([
        service.listCollaborators(widget.tripId),
        service.listInvites(widget.tripId),
      ]);
      if (mounted) {
        setState(() {
          _collaborators = results[0]
              as List<({String userId, String displayName, String email, String role})>;
          _invites =
              results[1] as List<({String id, String email, DateTime expiresAt})>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _sendInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(tripsApiServiceProvider).createInvite(widget.tripId, email);
      _emailController.clear();
      widget.onInvited(email);
      await _loadAll();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _revokeInvite(String inviteId) async {
    try {
      await ref.read(tripsApiServiceProvider).revokeInvite(widget.tripId, inviteId);
      await _loadAll();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _remove(String userId) async {
    try {
      await ref
          .read(tripsApiServiceProvider)
          .removeCollaborator(widget.tripId, userId);
      widget.onRemoved();
      await _loadAll();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _expiresIn(DateTime expiresAt) {
    final d = expiresAt.difference(DateTime.now());
    if (d.inDays >= 1) return 'expires in ${d.inDays}d';
    if (d.inHours >= 1) return 'expires in ${d.inHours}h';
    return 'expires soon';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collaborators = _collaborators;
    final invites = _invites;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          // Keep the email field above the keyboard.
          bottom: AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage access', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            // Invite by email (specs/invite-by-email): the friend gets a
            // single-use link; they appear below once they accept.
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: "Friend's email",
                      isDense: true,
                      prefixIcon: Icon(Icons.alternate_email, size: 18),
                    ),
                    onSubmitted: (_) => _sendInvite(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.tonal(
                  onPressed: _sending ? null : _sendInvite,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Invite'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (collaborators == null || invites == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (collaborators.isEmpty && invites.isEmpty)
                Text(
                  'No co-planners yet. Invite a friend by email above, or '
                  'copy an invite link from the share menu.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              for (final c in collaborators)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                      child: Icon(
                          c.role == 'viewer'
                              ? Icons.visibility_outlined
                              : Icons.person,
                          size: 18)),
                  title: Text(
                      c.displayName.isNotEmpty ? c.displayName : c.email),
                  subtitle: Text([
                    if (c.displayName.isNotEmpty) c.email,
                    c.role == 'viewer' ? 'Viewer' : 'Can edit',
                  ].join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Remove access',
                    onPressed: () => _remove(c.userId),
                  ),
                ),
              if (invites.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Pending invites',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                for (final inv in invites)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                        child: Icon(Icons.mail_outline, size: 18)),
                    title: Text(inv.email),
                    subtitle: Text('Invited — ${_expiresIn(inv.expiresAt)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Revoke invite',
                      onPressed: () => _revokeInvite(inv.id),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet with a drag-and-drop list for one itinerary section. Pops
/// with the reordered items on Save, or null on dismiss.
class _ReorderSectionSheet extends StatefulWidget {
  final List<ItineraryItem> items;
  const _ReorderSectionSheet({required this.items});

  @override
  State<_ReorderSectionSheet> createState() => _ReorderSectionSheetState();
}

class _ReorderSectionSheetState extends State<_ReorderSectionSheet> {
  late List<ItineraryItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reorder places', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Drag to change the visit order within this section.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: _items.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final moved = _items.removeAt(oldIndex);
                  _items.insert(newIndex, moved);
                });
              },
              itemBuilder: (context, i) {
                final item = _items[i];
                return ListTile(
                  key: ValueKey(item.id),
                  dense: true,
                  leading: Text('${i + 1}',
                      style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  title: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_indicator),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(_items),
                child: const Text('Save order'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
