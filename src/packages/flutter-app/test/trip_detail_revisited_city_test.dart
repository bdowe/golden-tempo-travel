import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';

import 'support/l10n_test_app.dart';

class _FakeTripsApiService extends TripsApiService {
  final Trip trip;
  _FakeTripsApiService(this.trip) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) async => trip;
}

ItineraryItem _item(int pos, String name, String city, int day) =>
    ItineraryItem(
      id: 'i$pos',
      position: pos,
      name: name,
      address: '$name street, $city-land',
      // Zero coords so the screen skips the map widget in the test env.
      latitude: 0,
      longitude: 0,
      category: 'attraction',
      day: day,
      city: city,
    );

void main() {
  // Regression: an itinerary that returns to a city (Athens → Fira → Oia →
  // Fira → Oia) builds two city groups with the same label. Keying the pinned
  // city headers by label handed one GlobalKey to two live widgets, which threw
  // "Multiple widgets used the same GlobalKey" and left the whole trip body
  // blank. Each run must get its own key.
  testWidgets('a trip that revisits a city renders both visits',
      (WidgetTester tester) async {
    final trip = Trip(
      id: 't1',
      title: 'Athens & Santorini',
      status: 'planned',
      createdAt: '2026-09-10',
      updatedAt: '2026-09-10',
      items: [
        _item(0, 'Acropolis', 'Athens', 1),
        _item(1, 'Ancient Agora', 'Athens', 2),
        _item(2, 'Fira town', 'Fira', 3),
        _item(3, 'Four Winds', 'Oia', 3),
        _item(4, 'Akrotiri', 'Fira', 4),
        _item(5, 'Oia sunset', 'Oia', 5),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
        ],
        child: MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          home: TripDetailScreen(tripId: 't1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The body built at all (the GlobalKey clash used to blank it out)...
    expect(tester.takeException(), isNull);
    expect(find.text('Acropolis'), findsOneWidget);
    // ...and each city that is visited twice has two pinned headers, one per
    // run, rather than one collapsed/duplicated header.
    expect(find.text('Fira'), findsNWidgets(2));
    expect(find.text('Oia'), findsNWidgets(2));
    expect(find.text('Athens'), findsOneWidget);
  });

  testWidgets('collapsing one visit leaves the other visit expanded',
      (WidgetTester tester) async {
    final trip = Trip(
      id: 't2',
      title: 'Athens & Santorini',
      status: 'planned',
      createdAt: '2026-09-10',
      updatedAt: '2026-09-10',
      items: [
        _item(0, 'Fira first stop', 'Fira', 1),
        _item(1, 'Oia detour', 'Oia', 2),
        _item(2, 'Fira second stop', 'Fira', 3),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
        ],
        child: MaterialApp(
          localizationsDelegates: testLocalizationsDelegates,
          home: TripDetailScreen(tripId: 't2'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fira first stop'), findsOneWidget);

    // Tap the first Fira header: that run's items go away, the second Fira
    // header stays (a label-keyed collapse set would have hidden both), and
    // the freed space reveals the next group's item.
    await tester.tap(find.text('Fira').first);
    await tester.pumpAndSettle();

    expect(find.text('Fira first stop'), findsNothing);
    expect(find.text('Fira'), findsNWidgets(2));
    expect(find.text('Oia detour'), findsOneWidget);
  });
}
