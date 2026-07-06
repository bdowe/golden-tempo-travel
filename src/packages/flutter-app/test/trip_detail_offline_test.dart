import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/providers/trip_cache_provider.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/trip_cache.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/widgets/offline_banner.dart';

/// getTrip answers from a queue: a Trip resolves, anything else throws it.
class _QueuedTripsApiService extends TripsApiService {
  final List<Object> responses;
  int calls = 0;

  _QueuedTripsApiService(this.responses)
      : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) {
    final next =
        responses[calls < responses.length ? calls : responses.length - 1];
    calls++;
    if (next is Trip) return Future.value(next);
    return Future.error(next);
  }
}

Trip _trip(String title) => Trip(
      id: 't1',
      title: title,
      status: 'planned',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      items: [
        // Zero coords so the screen skips the map widget in the test env.
        ItineraryItem(
          id: 'i0',
          position: 0,
          name: 'Acropolis',
          address: 'Athens, Greece',
          latitude: 0,
          longitude: 0,
          category: 'attraction',
        ),
      ],
    );

/// FilledButton.tonalIcon / TextButton.icon build private subclasses, so
/// byType-based finders miss them; match by subtype around the label instead.
T _labeledButton<T extends ButtonStyleButton>(
        WidgetTester tester, String label) =>
    tester.widget<T>(find.ancestor(
      of: find.text(label),
      matching: find.bySubtype<T>(),
    ));

Future<void> _pumpDetail(
    WidgetTester tester, _QueuedTripsApiService service, TripCache cache) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripsApiServiceProvider.overrideWithValue(service),
        tripCacheProvider.overrideWithValue(cache),
      ],
      child: MaterialApp(home: TripDetailScreen(tripId: 't1')),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('relativeTime', () {
    test('formats coarse staleness labels', () {
      final now = DateTime(2026, 7, 6, 12, 0);
      DateTime ago(Duration d) => now.subtract(d);
      expect(relativeTime(ago(const Duration(seconds: 20)), now: now),
          'just now');
      expect(relativeTime(ago(const Duration(minutes: 5)), now: now),
          '5 minutes ago');
      expect(
          relativeTime(ago(const Duration(hours: 1)), now: now), '1 hour ago');
      expect(
          relativeTime(ago(const Duration(days: 2)), now: now), '2 days ago');
    });
  });

  testWidgets(
      'network failure serves the cached trip read-only with an offline banner',
      (WidgetTester tester) async {
    final cache = TripCache('u1');
    await cache.writeTrip(_trip('Athens Trip'));
    final service =
        _QueuedTripsApiService([http.ClientException('connection refused')]);

    await _pumpDetail(tester, service, cache);
    await tester.pumpAndSettle();

    // The saved copy renders, clearly marked stale.
    expect(find.text('Acropolis'), findsOneWidget);
    expect(find.textContaining('Offline — showing saved copy from'),
        findsOneWidget);
    expect(find.text('Could not load this trip'), findsNothing);

    // Mutation affordances are disabled or hidden.
    final refine = _labeledButton<FilledButton>(tester, 'Refine with AI');
    expect(refine.onPressed, isNull, reason: 'chat/refine needs the network');
    final addPlace = _labeledButton<TextButton>(tester, 'Add place');
    expect(addPlace.onPressed, isNull);
    final rename = tester.widget<IconButton>(find.ancestor(
      of: find.byTooltip('Rename'),
      matching: find.byType(IconButton),
    ));
    expect(rename.onPressed, isNull);
    expect(find.byTooltip('Share trip'), findsNothing);
    expect(find.byTooltip('Delete trip'), findsNothing);
  });

  testWidgets('Retry re-fetches live and exits offline mode',
      (WidgetTester tester) async {
    final cache = TripCache('u1');
    await cache.writeTrip(_trip('Athens Trip'));
    final service = _QueuedTripsApiService(
        [http.ClientException('down'), _trip('Athens Trip (live)')]);

    await _pumpDetail(tester, service, cache);
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline — showing saved copy from'),
        findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(service.calls, 2);
    expect(find.textContaining('Offline — showing saved copy from'),
        findsNothing);
    expect(find.text('Athens Trip (live)'), findsWidgets);
    final refine = _labeledButton<FilledButton>(tester, 'Refine with AI');
    expect(refine.onPressed, isNotNull, reason: 'back online — re-enabled');
  });

  testWidgets('an HTTP 403 shows the error page, never the cached copy',
      (WidgetTester tester) async {
    final cache = TripCache('u1');
    await cache.writeTrip(_trip('Athens Trip'));
    final service =
        _QueuedTripsApiService([Exception('Failed to load trip (403)')]);

    await _pumpDetail(tester, service, cache);
    await tester.pumpAndSettle();

    expect(find.text('Could not load this trip'), findsOneWidget);
    expect(find.text('Acropolis'), findsNothing);
    expect(find.textContaining('Offline — showing saved copy from'),
        findsNothing);
  });

  testWidgets('a network failure with no cached copy shows the error page',
      (WidgetTester tester) async {
    final service = _QueuedTripsApiService([http.ClientException('down')]);

    await _pumpDetail(tester, service, TripCache('u1'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load this trip'), findsOneWidget);
    expect(find.textContaining('Offline — showing saved copy from'),
        findsNothing);
  });
}
