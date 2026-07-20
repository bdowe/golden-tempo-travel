import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/accommodation.dart';
import 'package:travel_route_planner/models/trip_segment.dart';
import 'package:travel_route_planner/utils/calendar_links.dart';

void main() {
  group('googleCalendarUrl', () {
    test('builds a prefilled all-day TEMPLATE link', () {
      final url = googleCalendarUrl(
        title: 'Stay: Casa do Brian',
        start: DateTime.utc(2026, 9, 4),
        endExclusive: DateTime.utc(2026, 9, 6),
        location: 'Lisbon',
        details: 'Airbnb',
      );
      final uri = Uri.parse(url);
      expect(uri.host, 'calendar.google.com');
      expect(uri.path, '/calendar/render');
      expect(uri.queryParameters['action'], 'TEMPLATE');
      expect(uri.queryParameters['text'], 'Stay: Casa do Brian');
      expect(uri.queryParameters['dates'], '20260904/20260906');
      expect(uri.queryParameters['location'], 'Lisbon');
      expect(uri.queryParameters['details'], 'Airbnb');
    });

    test('encodes reserved characters and omits empty optionals', () {
      final url = googleCalendarUrl(
        title: 'Fish & chips, maybe?',
        start: DateTime.utc(2026, 9, 4),
        endExclusive: DateTime.utc(2026, 9, 5),
        location: '  ',
      );
      final uri = Uri.parse(url);
      expect(uri.queryParameters['text'], 'Fish & chips, maybe?');
      expect(uri.queryParameters.containsKey('location'), isFalse);
      expect(uri.queryParameters.containsKey('details'), isFalse);
    });
  });

  group('stayCalendarRange', () {
    test('spans check-in to check-out (end-exclusive)', () {
      const a = Accommodation(
          id: 'a', name: 'Casa', checkIn: '2026-09-04', checkOut: '2026-09-06');
      final r = stayCalendarRange(a)!;
      expect(r.start, DateTime.utc(2026, 9, 4));
      expect(r.endExclusive, DateTime.utc(2026, 9, 6));
    });

    test('missing or non-later check-out falls back to one night', () {
      const noOut = Accommodation(id: 'a', name: 'Casa', checkIn: '2026-09-04');
      expect(stayCalendarRange(noOut)!.endExclusive, DateTime.utc(2026, 9, 5));
      const sameDay = Accommodation(
          id: 'a', name: 'Casa', checkIn: '2026-09-04', checkOut: '2026-09-04');
      expect(
          stayCalendarRange(sameDay)!.endExclusive, DateTime.utc(2026, 9, 5));
    });

    test('null for missing or unparseable check-in', () {
      expect(stayCalendarRange(const Accommodation(id: 'a', name: 'Casa')),
          isNull);
      expect(
          stayCalendarRange(const Accommodation(
              id: 'a', name: 'Casa', checkIn: 'not-a-date')),
          isNull);
    });
  });

  group('segmentCalendarRange', () {
    test('spans departure through arrival day inclusive', () {
      const s = TripSegment(
          id: 's',
          mode: 'flight',
          departDate: '2026-09-04',
          arriveDate: '2026-09-05');
      final r = segmentCalendarRange(s)!;
      expect(r.start, DateTime.utc(2026, 9, 4));
      expect(r.endExclusive, DateTime.utc(2026, 9, 6));
    });

    test('missing arrival is a single day; missing departure is null', () {
      const noArrive =
          TripSegment(id: 's', mode: 'flight', departDate: '2026-09-04');
      expect(segmentCalendarRange(noArrive)!.endExclusive,
          DateTime.utc(2026, 9, 5));
      expect(segmentCalendarRange(const TripSegment(id: 's', mode: 'flight')),
          isNull);
    });
  });

  group('itemCalendarRange', () {
    test('resolves trip start + (day - 1) as a single day', () {
      final r = itemCalendarRange('2026-08-01', 3)!;
      expect(r.start, DateTime.utc(2026, 8, 3));
      expect(r.endExclusive, DateTime.utc(2026, 8, 4));
    });

    test('null without a trip start, a day, or a valid day', () {
      expect(itemCalendarRange(null, 3), isNull);
      expect(itemCalendarRange('2026-08-01', null), isNull);
      expect(itemCalendarRange('2026-08-01', 0), isNull);
      expect(itemCalendarRange('nope', 3), isNull);
    });
  });
}
