import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/accommodation.dart';
import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';
import 'package:travel_route_planner/widgets/map_day_chips.dart';
import 'package:travel_route_planner/widgets/trip_map.dart';

class _FakeTripsApiService extends TripsApiService {
  final Trip trip;
  _FakeTripsApiService(this.trip) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) async => trip;
}

/// Real (tight Paris-cluster) coordinates so the trip detail screen mounts a
/// live TripMap instead of skipping it.
ItineraryItem _item(int pos, String name, double lat, double lng, int day) =>
    ItineraryItem(
      id: 'i$pos',
      position: pos,
      name: name,
      latitude: lat,
      longitude: lng,
      category: 'attraction',
      day: day,
      city: 'Paris',
    );

void main() {
  // Sept 1–3 => Day 1..3 chips; Day 3 deliberately has no items and no
  // covering stay, so selecting it exercises the on-map empty state.
  final trip = Trip(
    id: 't1',
    title: 'Paris',
    status: 'planned',
    createdAt: '2026-06-01',
    updatedAt: '2026-06-01',
    startDate: '2026-09-01',
    endDate: '2026-09-03',
    items: [
      _item(0, 'Louvre', 48.8606, 2.3376, 1),
      _item(1, 'Orsay', 48.8600, 2.3266, 1),
      _item(2, 'Pantheon', 48.8462, 2.3464, 2),
    ],
    accommodations: const [
      // Covers the night of day 1 only (checkout-exclusive).
      Accommodation(
        id: 'a1',
        name: 'Night One Hotel',
        latitude: 48.8630,
        longitude: 2.3364,
        checkIn: '2026-09-01',
        checkOut: '2026-09-02',
      ),
      // Covers the night of day 2 only.
      Accommodation(
        id: 'a2',
        name: 'Night Two Flat',
        latitude: 48.8520,
        longitude: 2.3330,
        checkIn: '2026-09-02',
        checkOut: '2026-09-03',
      ),
    ],
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
        ],
        child: MaterialApp(home: TripDetailScreen(tripId: 't1')),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the chip labelled [label] inside the map's chip row (the itinerary
  /// list renders its own "Day N" headers and an "All" category chip, so the
  /// find must be scoped to MapDayChips).
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(MapDayChips),
      matching: find.text(label),
    ));
    await tester.pump();
    await tester.pump(); // post-frame camera re-fit
  }

  TripMap map(WidgetTester tester) =>
      tester.widget<TripMap>(find.byType(TripMap));

  testWidgets('renders All + Day 1..N chips over the map',
      (WidgetTester tester) async {
    await pumpScreen(tester);

    final chips = find.byType(MapDayChips);
    expect(chips, findsOneWidget);
    for (final label in ['All', 'Day 1', 'Day 2', 'Day 3']) {
      expect(
        find.descendant(of: chips, matching: find.text(label)),
        findsOneWidget,
      );
    }
    // No chip beyond the trip's day count, and no "Unscheduled" chip.
    expect(find.descendant(of: chips, matching: find.text('Day 4')),
        findsNothing);
    expect(find.descendant(of: chips, matching: find.text('Unscheduled')),
        findsNothing);

    // All is the default: the map sees the whole trip.
    expect(map(tester).items, hasLength(3));
    expect(map(tester).accommodations, hasLength(2));
  });

  testWidgets('Day 2 filters the map to that day and its covering stay; '
      'All restores', (WidgetTester tester) async {
    await pumpScreen(tester);

    await tapChip(tester, 'Day 2');

    expect(map(tester).items.map((i) => i.name), ['Pantheon']);
    expect(map(tester).accommodations.map((a) => a.name), ['Night Two Flat']);
    expect(map(tester).fitSignature, 2);

    await tapChip(tester, 'All');

    expect(map(tester).items, hasLength(3));
    expect(map(tester).accommodations, hasLength(2));
    expect(map(tester).fitSignature, isNull);
  });

  testWidgets('a day with nothing mappable shows the on-map empty message '
      'while the chips stay', (WidgetTester tester) async {
    await pumpScreen(tester);

    await tapChip(tester, 'Day 3');

    expect(map(tester).items, isEmpty);
    expect(map(tester).accommodations, isEmpty);
    expect(find.text('No mapped places on this day'), findsOneWidget);
    // The chip row survives the empty selection (the gate is keyed to the
    // unfiltered items) and can navigate back out.
    expect(find.byType(MapDayChips), findsOneWidget);

    await tapChip(tester, 'All');
    expect(find.text('No mapped places on this day'), findsNothing);
    expect(map(tester).items, hasLength(3));
  });
}
