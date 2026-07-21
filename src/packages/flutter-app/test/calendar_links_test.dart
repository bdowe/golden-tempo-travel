import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/l10n/app_localizations.dart';
import 'package:travel_route_planner/models/accommodation.dart';
import 'package:travel_route_planner/models/itinerary_item.dart';
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

    test('builds a floating timed link with no Z suffix', () {
      final url = googleCalendarUrl(
        title: 'Acropolis',
        start: DateTime.utc(2026, 8, 3, 9),
        endExclusive: DateTime.utc(2026, 8, 3, 12),
        allDay: false,
      );
      final dates = Uri.parse(url).queryParameters['dates'];
      expect(dates, '20260803T090000/20260803T120000');
      // A Z would make Google read the pair as UTC and shift the event,
      // breaking parity with the floating .ics.
      expect(dates, isNot(contains('Z')));
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
    test('resolves trip start + (day - 1) as a single all-day', () {
      final r = itemCalendarRange('2026-08-01', 3)!;
      expect(r.start, DateTime.utc(2026, 8, 3));
      expect(r.endExclusive, DateTime.utc(2026, 8, 4));
      expect(r.allDay, isTrue);
    });

    test('null without a trip start, a day, or a valid day', () {
      expect(itemCalendarRange(null, 3), isNull);
      expect(itemCalendarRange('2026-08-01', null), isNull);
      expect(itemCalendarRange('2026-08-01', 0), isNull);
      expect(itemCalendarRange('nope', 3), isNull);
    });

    // These windows mirror itemTimeWindow in calendar_handler.go — the Go
    // table test asserts the same hours. Drift shows up as a diff here.
    test('time_of_day buckets become timed windows', () {
      const cases = {
        'morning': (9, 12),
        'afternoon': (13, 17),
        'evening': (19, 22),
      };
      cases.forEach((tod, hours) {
        final r = itemCalendarRange('2026-08-01', 3, timeOfDay: tod)!;
        expect(r.allDay, isFalse, reason: tod);
        expect(r.start, DateTime.utc(2026, 8, 3, hours.$1), reason: tod);
        expect(r.endExclusive, DateTime.utc(2026, 8, 3, hours.$2), reason: tod);
      });
    });

    test('empty or unknown time_of_day stays all-day', () {
      for (final tod in [null, '', 'night', 'whenever']) {
        final r = itemCalendarRange('2026-08-01', 3, timeOfDay: tod)!;
        expect(r.allDay, isTrue, reason: '$tod');
        expect(r.start, DateTime.utc(2026, 8, 3), reason: '$tod');
        expect(r.endExclusive, DateTime.utc(2026, 8, 4), reason: '$tod');
      }
    });

    test('timed windows survive a DST boundary', () {
      // 2026-10-25 is the EU DST change. Day 3 of a trip starting Oct 24 is
      // Oct 26 at 09:00 — this fails if anyone "fixes" the UTC wall-clock
      // carrier into local time.
      final r = itemCalendarRange('2026-10-24', 3, timeOfDay: 'morning')!;
      expect(r.start, DateTime.utc(2026, 10, 26, 9));
      expect(r.endExclusive, DateTime.utc(2026, 10, 26, 12));
    });
  });

  group('displayUrl', () {
    test('strips scheme, www, query, and trailing slash', () {
      expect(
          displayUrl('https://www.booking.com/hotel/gr/grande.html?aid=42&x=1'),
          'booking.com/hotel/gr/grande.html');
      expect(displayUrl('http://example.com/'), 'example.com');
      expect(displayUrl(null), '');
      expect(displayUrl('  '), '');
      expect(displayUrl('not a url'), 'not a url');
    });

    test('truncates long links with an ellipsis', () {
      final long = 'https://example.com/${'very-long-path/' * 10}';
      final got = displayUrl(long);
      expect(got.runes.length, lessThanOrEqualTo(48));
      expect(got, endsWith('…'));
    });
  });

  group('calendar details', () {
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    // Expected strings mirror icsStayDescription / icsSegmentDescription /
    // icsItemDescription in the Go suite (calendar_test.go).
    test('stay details join provider, price, booked, and link', () {
      const a = Accommodation(
        id: 'a',
        name: 'Casa',
        provider: 'Booking.com',
        priceNote: '€180/night',
        url: 'https://www.booking.com/hotel/gr/grande.html?aid=42',
        booked: true,
      );
      expect(stayCalendarDetails(l10n, a),
          'Booking.com · €180/night · Booked · booking.com/hotel/gr/grande.html');
    });

    test('unbooked stay omits the flag and empties leave no separators', () {
      const a = Accommodation(
          id: 'a', name: 'Casa', priceNote: '€180/night', booked: false);
      expect(stayCalendarDetails(l10n, a), '€180/night');
      expect(
          stayCalendarDetails(l10n, const Accommodation(id: 'a', name: 'Casa')),
          '');
    });

    test('segment details include notes between booked and the link', () {
      const s = TripSegment(
        id: 's',
        mode: 'flight',
        provider: 'Delta',
        priceNote: r'$780',
        notes: 'Departs 6:30 PM',
        url: 'https://www.delta.com/booking/xyz',
        booked: true,
      );
      expect(segmentCalendarDetails(l10n, s),
          r'Delta · $780 · Booked · Departs 6:30 PM · delta.com/booking/xyz');
    });

    test('item details capitalize time-of-day and credit the local', () {
      const item = ItineraryItem(
        id: 'i',
        position: 0,
        name: 'Acropolis',
        latitude: 37.97,
        longitude: 23.72,
        timeOfDay: 'morning',
        localSourceName: 'Maria',
      );
      expect(itemCalendarDetails(l10n, item), 'Morning · Recommended by Maria');
      expect(
          itemCalendarDetails(
              l10n,
              const ItineraryItem(
                  id: 'i',
                  position: 0,
                  name: 'X',
                  latitude: 0,
                  longitude: 0)),
          '');
    });
  });
}
