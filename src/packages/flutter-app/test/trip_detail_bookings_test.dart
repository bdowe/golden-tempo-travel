import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/trip.dart';
import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/models/booking_todo.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/trips_api_service.dart';
import 'package:travel_route_planner/providers/trips_provider.dart';
import 'package:travel_route_planner/screens/trip_detail_screen.dart';
import 'package:travel_route_planner/widgets/booking_todo_card.dart';

/// Returns a fixed trip without hitting the network, so we can exercise the
/// real TripDetailScreen render path. The booking-todo sync call fails in the
/// test env and is swallowed, so the todos seeded on the trip survive.
class _FakeTripsApiService extends TripsApiService {
  final Trip trip;
  _FakeTripsApiService(this.trip) : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<Trip> getTrip(String id) async => trip;
}

ItineraryItem _item(int pos, String name, String address, String category,
        {int? day, String? city}) =>
    ItineraryItem(
      id: 'i$pos',
      position: pos,
      name: name,
      address: address,
      // Zero coords so the screen skips the map widget in the test env.
      latitude: 0,
      longitude: 0,
      category: category,
      day: day,
      city: city,
    );

BookingTodo _todo(String kind, String key, String title, {bool auto = true}) =>
    BookingTodo(id: key, kind: kind, todoKey: key, title: title, auto: auto);

void main() {
  testWidgets('city-matched bookings embed in their group; rest are residual',
      (WidgetTester tester) async {
    final trip = Trip(
      id: 't1',
      title: 'Europe',
      status: 'planned',
      startDate: '2026-06-10',
      endDate: '2026-06-13',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      items: [
        _item(0, 'Louvre', 'Paris, France', 'attraction', day: 1, city: 'Paris'),
        _item(1, 'Café de Flore', 'Paris, France', 'restaurant', day: 2, city: 'Paris'),
        _item(2, 'Colosseum', 'Rome, Italy', 'attraction', day: 3, city: 'Rome'),
        _item(3, 'Trastevere', 'Rome, Italy', 'restaurant', day: 4, city: 'Rome'),
      ],
      bookingTodos: [
        _todo('transport', 'transport:jfk>>paris', 'JFK → Paris'),
        _todo('stay', 'stay:paris', 'Stay in Paris'),
        _todo('transport', 'transport:paris>>rome', 'Paris → Rome'),
        _todo('stay', 'stay:rome', 'Stay in Rome'),
        _todo('transport', 'transport:rome>>jfk', 'Rome → JFK'),
        _todo('other', 'custom:x', 'Museum tickets', auto: false),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
        ],
        child: MaterialApp(home: TripDetailScreen(tripId: 't1')),
      ),
    );
    await tester.pumpAndSettle();

    // City-matched bookings render once each, as compact embedded rows.
    expect(find.widgetWithText(BookingTodoRow, 'Stay in Paris'), findsOneWidget);
    expect(find.widgetWithText(BookingTodoRow, 'Stay in Rome'), findsOneWidget);
    expect(find.widgetWithText(BookingTodoRow, 'JFK → Paris'), findsOneWidget);
    expect(find.widgetWithText(BookingTodoRow, 'Paris → Rome'), findsOneWidget);
    expect(find.widgetWithText(BookingTodoRow, 'Rome → JFK'), findsOneWidget);

    // Arrival + stay sit above the city's first item; the return flight home
    // comes after the last city's last item.
    expect(tester.getTopLeft(find.text('JFK → Paris')).dy,
        lessThan(tester.getTopLeft(find.text('Louvre')).dy));
    expect(tester.getTopLeft(find.text('Paris → Rome')).dy,
        lessThan(tester.getTopLeft(find.text('Colosseum')).dy));
    expect(tester.getTopLeft(find.text('Rome → JFK')).dy,
        greaterThan(tester.getTopLeft(find.text('Trastevere')).dy));

    // Only the unmatched custom todo remains in "Other bookings", as a card.
    expect(find.text('Other bookings'), findsOneWidget);
    expect(find.byType(BookingTodoCard), findsOneWidget);
    expect(find.widgetWithText(BookingTodoCard, 'Museum tickets'), findsOneWidget);
  });

  testWidgets('collapsing a city hides its embedded booking rows',
      (WidgetTester tester) async {
    final trip = Trip(
      id: 't2',
      title: 'Weekend away',
      status: 'planned',
      startDate: '2026-06-10',
      endDate: '2026-06-12',
      createdAt: '2026-06-01',
      updatedAt: '2026-06-01',
      items: [
        _item(0, 'Louvre', 'Paris, France', 'attraction', day: 1, city: 'Paris'),
      ],
      bookingTodos: [
        _todo('transport', 'transport:jfk>>paris', 'JFK → Paris'),
        _todo('stay', 'stay:paris', 'Stay in Paris'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripsApiServiceProvider.overrideWithValue(_FakeTripsApiService(trip)),
        ],
        child: MaterialApp(home: TripDetailScreen(tripId: 't2')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BookingTodoRow), findsNWidgets(2));

    // No unmatched bookings -> no "Other bookings" section, just the inline
    // add affordance.
    expect(find.text('Other bookings'), findsNothing);
    expect(find.text('Add booking'), findsOneWidget);

    await tester.tap(find.text('Paris'));
    await tester.pumpAndSettle();

    expect(find.byType(BookingTodoRow), findsNothing);
    expect(find.text('Louvre'), findsNothing);
  });
}
