import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';
import 'package:travel_route_planner/widgets/trip_refine_panel.dart';

import 'support/l10n_test_app.dart';

/// Mobile declutter, header half: on narrow the meta row drops the Refine
/// button (it becomes an app-bar sparkle) and the dates chip humanizes.
class _FakeTripsApiService extends TripsApiService {
  final Trip trip;
  _FakeTripsApiService(this.trip) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) async => trip;
}

Trip _trip({String? access}) => Trip(
      id: 't1',
      title: 'Sevilla week',
      status: 'planned',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      startDate: '2026-09-01',
      endDate: '2026-09-03',
      access: access,
      ownerName: access == null ? null : 'Brian',
      items: [
        ItineraryItem(
          id: 'i0',
          position: 0,
          name: 'Real Alcázar',
          latitude: 0,
          longitude: 0,
          category: 'attraction',
          day: 1,
          city: 'Sevilla',
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, Trip trip,
    {required Size surface}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
      ],
      child: MaterialApp(
        localizationsDelegates: testLocalizationsDelegates,
        home: const TripDetailScreen(tripId: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const phone = Size(390, 844);

  testWidgets('narrow owner: sparkle in app bar opens refine; dates humanize',
      (tester) async {
    await _pump(tester, _trip(), surface: phone);

    // Meta row: no Refine button, humanized dates instead of raw ISO.
    expect(find.text('Refine with AI'), findsNothing);
    expect(find.textContaining('2026-09-01'), findsNothing);
    expect(find.text('Sep 1 – Sep 3'), findsOneWidget);

    // The app-bar sparkle opens the refine panel (narrow => sheet).
    final sparkle = find.byTooltip('Refine with AI');
    expect(sparkle, findsOneWidget);
    await tester.tap(sparkle);
    await tester.pumpAndSettle();
    expect(find.byType(TripRefinePanel), findsOneWidget);
  });

  testWidgets('narrow editor collaborator keeps the sparkle (spec)',
      (tester) async {
    await _pump(tester, _trip(access: 'editor'), surface: phone);
    expect(find.byTooltip('Refine with AI'), findsOneWidget);
  });

  testWidgets('narrow viewer never gets the sparkle', (tester) async {
    await _pump(tester, _trip(access: 'viewer'), surface: phone);
    expect(find.byTooltip('Refine with AI'), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  testWidgets('wide keeps the header button and raw ISO dates; no sparkle',
      (tester) async {
    await _pump(tester, _trip(), surface: const Size(1200, 900));
    expect(find.text('Refine with AI'), findsOneWidget);
    expect(find.text('2026-09-01 → 2026-09-03'), findsOneWidget);
    expect(find.byTooltip('Refine with AI'), findsNothing);
  });
}
