import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';
import 'package:travel_route_planner/widgets/map_day_chips.dart';
import 'package:travel_route_planner/widgets/status_pill.dart';

/// Today mode (specs/today-mode PR 3): one-shot auto-scroll to today's day
/// header, the pinned "Today" jump chip, and the header highlight.
///
/// Dates are computed relative to DateTime.now() so "today" is always live.
/// Items carry zero coordinates so the map sliver is skipped — the scroll
/// math must land correctly with the map-hidden pinned-chrome height.
class _FakeTripsApiService extends TripsApiService {
  final Trip trip;
  int calls = 0;
  _FakeTripsApiService(this.trip) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) async {
    calls++;
    return trip;
  }
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

ItineraryItem _item(int pos, String name, int day,
        {double lat = 0, double lng = 0}) =>
    ItineraryItem(
      id: 'i$pos',
      position: pos,
      name: name,
      address: '$name street, Paris',
      latitude: lat,
      longitude: lng,
      category: 'attraction',
      day: day,
      city: 'Paris',
    );

/// A three-day Paris trip: day 1 is long enough that today's (day 2) header
/// starts well below the fold, day 3 gives the scroll room to land day 2 at
/// the top.
Trip _liveTrip({required String startDate, required String endDate}) => Trip(
      id: 't1',
      title: 'Live Trip',
      status: 'planned',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      startDate: startDate,
      endDate: endDate,
      items: [
        for (var k = 0; k < 6; k++) _item(k, 'Past stop $k', 1),
        for (var k = 0; k < 6; k++) _item(6 + k, 'Today stop $k', 2),
        for (var k = 0; k < 4; k++) _item(12 + k, 'Next stop $k', 3),
      ],
    );

Future<void> _pumpScreen(WidgetTester tester, TripsApiService service) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tripsApiServiceProvider.overrideWithValue(service)],
      child: const MaterialApp(home: TripDetailScreen(tripId: 't1')),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// The "Today" StatusPill inside today's day header (the jump chip is an
/// ActionChip, so the two never collide).
Finder _todayPill() => find.widgetWithText(StatusPill, 'Today');

Finder _todayChip() => find.widgetWithText(ActionChip, 'Today');

void main() {
  final now = DateTime.now();
  // Today is day 2 of a 3-day trip that started yesterday.
  final start = _iso(now.subtract(const Duration(days: 1)));
  final end = _iso(now.add(const Duration(days: 1)));

  testWidgets(
      'live trip auto-scrolls once to today: header rests just below the '
      'pinned chrome, tinted, with a Today pill and jump chip',
      (WidgetTester tester) async {
    await _pumpScreen(
        tester, _FakeTripsApiService(_liveTrip(startDate: start, endDate: end)));

    // The one-shot scroll actually moved the list.
    expect(_position(tester).pixels, greaterThan(0));

    // Today's header carries the pill and the highlight tint (opaque: the
    // primary tint alpha-blended onto the scaffold background).
    expect(_todayPill(), findsOneWidget);
    final theme = Theme.of(tester.element(find.text('Itinerary')));
    final expectedTint = Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: 0.06),
        theme.scaffoldBackgroundColor);
    final headerMaterial = tester.widget<Material>(find
        .ancestor(of: _todayPill(), matching: find.byType(Material))
        .first);
    expect(headerMaterial.color, expectedTint);

    // The header sits just below the pinned chrome: with zero-coord items
    // the map sliver is skipped, so the chrome is the itinerary title header
    // (100) plus the pinned city header above the day header.
    final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    final pillDy = tester.getTopLeft(_todayPill()).dy;
    expect(pillDy, greaterThan(viewportTop + 100));
    expect(pillDy, lessThan(viewportTop + 100 + 120));
    // Today's items start right under it.
    expect(find.text('Today stop 0'), findsOneWidget);

    // The jump chip renders in the pinned title row.
    expect(_todayChip(), findsOneWidget);
  });

  testWidgets('a silent refresh never re-triggers the auto-scroll (one-shot)',
      (WidgetTester tester) async {
    final service =
        _FakeTripsApiService(_liveTrip(startDate: start, endDate: end));
    await _pumpScreen(tester, service);
    expect(_position(tester).pixels, greaterThan(0));

    // Scroll back to the top, then drive a silent refresh through the fake
    // service via pull-to-refresh.
    _position(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(service.calls, greaterThan(1)); // the refresh really refetched
    expect(_position(tester).pixels, 0); // ...and did not scroll
  });

  testWidgets('the Today chip expands a collapsed today section and scrolls',
      (WidgetTester tester) async {
    await _pumpScreen(
        tester, _FakeTripsApiService(_liveTrip(startDate: start, endDate: end)));

    // Collapse today's day by tapping its header (the pill sits inside the
    // header's InkWell), then park the list at the top.
    await tester.tap(_todayPill());
    await tester.pumpAndSettle();
    expect(find.text('Today stop 0'), findsNothing);
    _position(tester).jumpTo(0);
    await tester.pumpAndSettle();

    await tester.tap(_todayChip());
    await tester.pumpAndSettle();

    // Expanded and scrolled: today's items are back and the header rests
    // below the pinned chrome again.
    expect(_position(tester).pixels, greaterThan(0));
    expect(find.text('Today stop 0'), findsOneWidget);
    final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    final pillDy = tester.getTopLeft(_todayPill()).dy;
    expect(pillDy, greaterThan(viewportTop + 100));
    expect(pillDy, lessThan(viewportTop + 100 + 120));
  });

  testWidgets('a trip that ended yesterday gets no Today behavior',
      (WidgetTester tester) async {
    final trip = _liveTrip(
      startDate: _iso(now.subtract(const Duration(days: 3))),
      endDate: _iso(now.subtract(const Duration(days: 1))),
    );
    await _pumpScreen(tester, _FakeTripsApiService(trip));

    expect(_position(tester).pixels, 0);
    expect(_todayChip(), findsNothing);
    expect(_todayPill(), findsNothing);
  });

  testWidgets('an undated trip gets no Today behavior',
      (WidgetTester tester) async {
    final undated = Trip(
      id: 't1',
      title: 'Undated Trip',
      status: 'planned',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      items: [
        for (var k = 0; k < 6; k++) _item(k, 'Stop $k', 1),
        for (var k = 0; k < 6; k++) _item(6 + k, 'Later stop $k', 2),
      ],
    );
    await _pumpScreen(tester, _FakeTripsApiService(undated));

    expect(_position(tester).pixels, 0);
    expect(_todayChip(), findsNothing);
    expect(_todayPill(), findsNothing);
    expect(find.text('Day 1'), findsOneWidget); // plain headers, no dates
  });

  testWidgets('a live trip preselects today on the map day chips',
      (WidgetTester tester) async {
    // Real (tight Paris-cluster) coordinates so the map sliver mounts — the
    // auto-scroll then also exercises the map-shown pinned-chrome height.
    final trip = Trip(
      id: 't1',
      title: 'Live Mapped Trip',
      status: 'planned',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      startDate: start,
      endDate: end,
      items: [
        _item(0, 'Louvre', 1, lat: 48.8606, lng: 2.3376),
        _item(1, 'Orsay', 1, lat: 48.8600, lng: 2.3266),
        _item(2, 'Pantheon', 2, lat: 48.8462, lng: 2.3464),
      ],
    );
    await _pumpScreen(tester, _FakeTripsApiService(trip));

    expect(
        tester.widget<MapDayChips>(find.byType(MapDayChips)).selected, 2);
    expect(_todayChip(), findsOneWidget);
  });
}
