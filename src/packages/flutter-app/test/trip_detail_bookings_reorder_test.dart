import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/accommodation.dart';
import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/models/trip_segment.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/booking_drafts_api_service.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/providers/booking_drafts_provider.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';

import 'support/l10n_test_app.dart';

/// Returns a fixed trip without hitting the network, so we can exercise the
/// real TripDetailScreen render path.
class _FakeTripsApiService extends TripsApiService {
  final Trip trip;
  _FakeTripsApiService(this.trip) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) async => trip;
}

/// syncDrafts fails (the screen swallows it, so the stays/segments seeded on
/// the trip survive); reorder calls are recorded and optionally fail.
class _FakeBookingDraftsApiService extends BookingDraftsApiService {
  final List<({List<String>? stayIds, List<String>? segmentIds})>
      reorderCalls = [];
  final bool failReorder;
  _FakeBookingDraftsApiService({this.failReorder = false})
      : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<BookingDraftsResult> syncDrafts(
          String tripId, Map<String, dynamic> payload) async =>
      throw Exception('offline test env');

  @override
  Future<void> reorderBookings(String tripId,
      {List<String>? stayIds, List<String>? segmentIds}) async {
    reorderCalls.add((stayIds: stayIds, segmentIds: segmentIds));
    if (failReorder) throw Exception('server said no');
  }
}

Accommodation _stay(String id, String name, {bool auto = false}) =>
    Accommodation(
        id: id, name: name, auto: auto, autoKey: auto ? 'stay:$id' : null);

TripSegment _segment(String id, String origin, String destination) =>
    TripSegment(id: id, mode: 'flight', origin: origin, destination: destination);

Trip _trip(List<Accommodation> stays, List<TripSegment> segments) => Trip(
      id: 't1',
      title: 'Lisbon hop',
      status: 'planned',
      startDate: '2026-09-01',
      endDate: '2026-09-06',
      createdAt: '2026-08-01',
      updatedAt: '2026-08-01',
      items: [],
      accommodations: stays,
      segments: segments,
    );

/// The itinerary renders lazily (slivers), so widgets below the default
/// 800x600 test viewport never get built. A tall viewport keeps the whole
/// page — including the trailing bookings section — built and findable.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<_FakeBookingDraftsApiService> _pumpTrip(WidgetTester tester, Trip trip,
    {bool failReorder = false}) async {
  final fake = _FakeBookingDraftsApiService(failReorder: failReorder);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
        bookingDraftsApiServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,home: TripDetailScreen(tripId: 't1')),
    ),
  );
  await tester.pumpAndSettle();
  // The hub's stays/transport groups render behind a collapsed one-line
  // Bookings row — expand it first.
  await tester.ensureVisible(find.text('Bookings'));
  await tester.tap(find.text('Bookings'));
  await tester.pumpAndSettle();
  return fake;
}

/// Drags the handle inside the ListTile containing [title] vertically by [dy].
Future<void> _dragRow(WidgetTester tester, String title, double dy) async {
  final row = find.ancestor(
      of: find.text(title), matching: find.byType(ListTile));
  final handle = find.descendant(
      of: row, matching: find.byIcon(Icons.drag_indicator));
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await tester.pump(const Duration(milliseconds: 100));
  for (var i = 0; i < 5; i++) {
    await gesture.moveBy(Offset(0, dy / 5));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

double _rowTop(WidgetTester tester, String title) => tester
    .getTopLeft(
        find.ancestor(of: find.text(title), matching: find.byType(ListTile)))
    .dy;

void main() {
  testWidgets('stay drag reorders stays only and persists via the service',
      (WidgetTester tester) async {
    _useTallViewport(tester);
    final fake = await _pumpTrip(
      tester,
      _trip(
        [
          _stay('a', 'Hotel Alpha'),
          _stay('b', 'Hotel Beta'),
          _stay('d', 'Suggested Stay', auto: true),
        ],
        [_segment('g1', 'JFK', 'LIS'), _segment('g2', 'LIS', 'JFK')],
      ),
    );

    // A handle on every stay row (incl. the Suggested draft) and segment row.
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(5));

    final rowHeight =
        _rowTop(tester, 'Hotel Beta') - _rowTop(tester, 'Hotel Alpha');
    await _dragRow(tester, 'Hotel Alpha', rowHeight + 20);

    expect(fake.reorderCalls.length, 1);
    expect(fake.reorderCalls.single.stayIds, ['b', 'a', 'd']);
    expect(fake.reorderCalls.single.segmentIds, isNull);
    // Optimistic order is visible.
    expect(_rowTop(tester, 'Hotel Beta'),
        lessThan(_rowTop(tester, 'Hotel Alpha')));
    expect(_rowTop(tester, 'Hotel Alpha'),
        lessThan(_rowTop(tester, 'Suggested Stay')));
  });

  testWidgets('segment drag sends segment_ids only',
      (WidgetTester tester) async {
    _useTallViewport(tester);
    final fake = await _pumpTrip(
      tester,
      _trip(
        [_stay('a', 'Hotel Alpha'), _stay('b', 'Hotel Beta')],
        [_segment('g1', 'JFK', 'LIS'), _segment('g2', 'LIS', 'JFK')],
      ),
    );

    final rowHeight = _rowTop(tester, 'LIS → JFK') - _rowTop(tester, 'JFK → LIS');
    await _dragRow(tester, 'JFK → LIS', rowHeight + 20);

    expect(fake.reorderCalls.length, 1);
    expect(fake.reorderCalls.single.segmentIds, ['g2', 'g1']);
    expect(fake.reorderCalls.single.stayIds, isNull);
    expect(_rowTop(tester, 'LIS → JFK'), lessThan(_rowTop(tester, 'JFK → LIS')));
  });

  testWidgets('failed reorder reverts the order and shows a snackbar',
      (WidgetTester tester) async {
    _useTallViewport(tester);
    final fake = await _pumpTrip(
      tester,
      _trip([_stay('a', 'Hotel Alpha'), _stay('b', 'Hotel Beta')], []),
      failReorder: true,
    );

    final rowHeight =
        _rowTop(tester, 'Hotel Beta') - _rowTop(tester, 'Hotel Alpha');
    await _dragRow(tester, 'Hotel Alpha', rowHeight + 20);

    expect(fake.reorderCalls.length, 1);
    expect(_rowTop(tester, 'Hotel Alpha'),
        lessThan(_rowTop(tester, 'Hotel Beta')));
    expect(find.textContaining('Could not reorder'), findsOneWidget);
  });

  testWidgets('a single-row group gets no drag handle',
      (WidgetTester tester) async {
    _useTallViewport(tester);
    await _pumpTrip(
      tester,
      _trip(
        [_stay('a', 'Hotel Alpha'), _stay('b', 'Hotel Beta')],
        [_segment('g1', 'JFK', 'LIS')],
      ),
    );

    // Two stay handles, zero segment handles.
    expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
    final segmentRow = find.ancestor(
        of: find.text('JFK → LIS'), matching: find.byType(ListTile));
    expect(
        find.descendant(
            of: segmentRow, matching: find.byIcon(Icons.drag_indicator)),
        findsNothing);
  });
}
