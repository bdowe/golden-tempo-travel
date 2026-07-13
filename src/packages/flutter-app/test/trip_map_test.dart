import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/accommodation.dart';
import 'package:travel_route_planner/models/itinerary_item.dart';
import 'package:travel_route_planner/widgets/trip_map.dart';

ItineraryItem _item(int pos, String name, double lat, double lng) =>
    ItineraryItem(
      id: 'i$pos',
      position: pos,
      name: name,
      latitude: lat,
      longitude: lng,
      category: 'attraction',
    );

/// Hosts the map at a fixed size (FlutterMap needs bounded constraints).
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 400, height: 300, child: child),
        ),
      ),
    );

void main() {
  // Tight cluster of Paris-area coordinates so every marker stays in the
  // viewport at the auto-fit zoom.
  final items = [
    _item(0, 'Louvre', 48.8606, 2.3376),
    _item(1, 'Café de Flore', 48.8540, 2.3326),
  ];

  testWidgets('builds without accommodations (default keeps old call sites)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(TripMap(items: items)));
    await tester.pump();

    expect(find.byType(TripMap), findsOneWidget);
    expect(find.byIcon(Icons.hotel), findsNothing);
  });

  testWidgets('renders one stay marker per stay with coordinates',
      (WidgetTester tester) async {
    const stays = [
      Accommodation(
        id: 'a1',
        name: 'Hôtel du Louvre',
        latitude: 48.8630,
        longitude: 2.3364,
        checkIn: '2026-06-10',
        checkOut: '2026-06-12',
      ),
      Accommodation(
        id: 'a2',
        name: 'Left Bank Flat',
        latitude: 48.8520,
        longitude: 2.3330,
      ),
      // No coordinates: must be skipped, not plotted at (0, 0).
      Accommodation(id: 'a3', name: 'Ungeocoded Stay'),
    ];

    await tester.pumpWidget(
      _host(TripMap(items: items, accommodations: stays)),
    );
    await tester.pump();

    expect(find.byIcon(Icons.hotel), findsNWidgets(2));

    // Tapping a stay is a tooltip affair (name + dates), not selection sync.
    final tooltips = tester
        .widgetList<Tooltip>(find.ancestor(
          of: find.byIcon(Icons.hotel),
          matching: find.byType(Tooltip),
        ))
        .map((t) => t.message)
        .toList();
    expect(tooltips, contains('Hôtel du Louvre\nJun 10 – Jun 12'));
    expect(tooltips, contains('Left Bank Flat')); // no dates -> name only
  });

  testWidgets('custom emptyLabel renders when nothing is mappable',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(const TripMap(items: [], emptyLabel: 'No mapped places on Day 3')),
    );
    await tester.pump();

    expect(find.text('No mapped places on Day 3'), findsOneWidget);
    expect(find.text('No mapped places'), findsNothing);
  });

  testWidgets('default emptyLabel keeps the existing message',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const TripMap(items: [])));
    await tester.pump();

    expect(find.text('No mapped places'), findsOneWidget);
  });

  testWidgets('changing fitSignature re-fits without crashing (smoke)',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(TripMap(items: items, fitSignature: 'all')),
    );
    await tester.pump();

    // Filtered down to one item under a new signature: the post-frame re-fit
    // must run against the live controller without throwing.
    await tester.pumpWidget(
      _host(TripMap(items: [items.first], fitSignature: 'day-1')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(TripMap), findsOneWidget);

    // Signature change while nothing is mappable (empty state, no live map)
    // must be a no-op, not a crash.
    await tester.pumpWidget(
      _host(const TripMap(items: [], fitSignature: 'day-2')),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No mapped places'), findsOneWidget);
  });

  testWidgets('stays alone (no mapped items) still render a map',
      (WidgetTester tester) async {
    const stays = [
      Accommodation(
        id: 'a1',
        name: 'Hôtel du Louvre',
        latitude: 48.8630,
        longitude: 2.3364,
      ),
    ];

    await tester.pumpWidget(
      _host(const TripMap(items: [], accommodations: stays)),
    );
    await tester.pump();

    expect(find.text('No mapped places'), findsNothing);
    expect(find.byIcon(Icons.hotel), findsOneWidget);
  });
}
