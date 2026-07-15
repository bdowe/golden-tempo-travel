import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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

/// The live camera of the mounted FlutterMap, read from an element inside its
/// subtree (TileLayer is always present).
MapCamera _camera(WidgetTester tester) =>
    MapCamera.of(tester.element(find.byType(TileLayer).first));

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

  testWidgets(
      'adding a far-away item with unchanged fitSignature re-fits the camera '
      'to contain all points', (WidgetTester tester) async {
    await tester.pumpWidget(_host(TripMap(items: items, fitSignature: 'all')));
    await tester.pump();

    // Marseille: well outside the Paris-fit viewport, so the final assertions
    // below are exactly what the pre-fix code violates.
    const far = LatLng(43.2965, 5.3698);
    expect(_camera(tester).visibleBounds.contains(far), isFalse);

    await tester.pumpWidget(_host(TripMap(
      items: [...items, _item(2, 'Vieux-Port', far.latitude, far.longitude)],
      fitSignature: 'all', // unchanged — the bug condition
    )));
    await tester.pump(); // frame rendering the new pin schedules the re-fit
    await tester.pump(); // post-frame callback has run; camera updated

    final bounds = _camera(tester).visibleBounds;
    expect(bounds.contains(far), isTrue);
    for (final it in items) {
      expect(bounds.contains(LatLng(it.latitude, it.longitude)), isTrue);
    }
  });

  testWidgets('content change while a pin is selected does not yank the camera',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(TripMap(items: items, selectedPosition: 0, fitSignature: 'all')),
    );
    await tester.pump();

    // Initial mount centers on the selected item at zoom 15.
    expect(_camera(tester).zoom, 15);

    const far = LatLng(43.2965, 5.3698);
    await tester.pumpWidget(_host(TripMap(
      items: [...items, _item(2, 'Vieux-Port', far.latitude, far.longitude)],
      selectedPosition: 0,
      fitSignature: 'all',
    )));
    await tester.pump();
    await tester.pump();

    final camera = _camera(tester);
    expect(camera.zoom, 15);
    expect(camera.center.latitude, closeTo(48.8606, 1e-4)); // still on Louvre
    expect(camera.visibleBounds.contains(far), isFalse);
  });

  testWidgets('empty state to mapped content frames all points',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(const TripMap(items: [])));
    await tester.pump();
    expect(find.text('No mapped places'), findsOneWidget);

    await tester.pumpWidget(_host(TripMap(items: items)));
    await tester.pump();
    await tester.pump();

    final bounds = _camera(tester).visibleBounds;
    for (final it in items) {
      expect(bounds.contains(LatLng(it.latitude, it.longitude)), isTrue);
    }
  });

  testWidgets('reordering items does not move the camera',
      (WidgetTester tester) async {
    await tester.pumpWidget(_host(TripMap(items: items)));
    await tester.pump();

    final before = _camera(tester);
    await tester.pumpWidget(
      _host(TripMap(items: items.reversed.toList())),
    );
    await tester.pump();
    await tester.pump();

    final after = _camera(tester);
    expect(after.zoom, before.zoom);
    expect(after.center, before.center);
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
