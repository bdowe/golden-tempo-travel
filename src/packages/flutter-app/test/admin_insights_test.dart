import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/admin_insights.dart';

void main() {
  group('AdminTimeseries.denseSeries', () {
    final start = DateTime.utc(2026, 7, 1);

    test('zero-fills missing days across the whole window', () {
      final ts = AdminTimeseries(
        days: 5,
        startDay: start,
        series: {
          'user_registered': [
            DailyCount(day: DateTime.utc(2026, 7, 2), n: 3),
            DailyCount(day: DateTime.utc(2026, 7, 5), n: 1),
          ],
        },
      );

      final dense = ts.denseSeries('user_registered');
      expect(dense.length, 5);
      expect(dense.map((c) => c.n), [0, 3, 0, 0, 1]);
      expect(dense.first.day, start);
      expect(dense.last.day, DateTime.utc(2026, 7, 5));
    });

    test('unknown key yields an all-zero window (stable chart slots)', () {
      final ts = AdminTimeseries(days: 3, startDay: start, series: const {});
      final dense = ts.denseSeries('landing_viewed');
      expect(dense.length, 3);
      expect(dense.every((c) => c.n == 0), isTrue);
    });

    test('crosses month boundaries day by day', () {
      final ts = AdminTimeseries(
        days: 3,
        startDay: DateTime.utc(2026, 6, 29),
        series: {
          'trip_created': [DailyCount(day: DateTime.utc(2026, 7, 1), n: 2)],
        },
      );
      final dense = ts.denseSeries('trip_created');
      expect(dense.map((c) => c.n), [0, 0, 2]);
      expect(dense.last.day, DateTime.utc(2026, 7, 1));
    });

    test('parses the API payload shape (sparse map of day lists)', () {
      final ts = AdminTimeseries.fromJson({
        'days': 2,
        'start_day': '2026-07-01T00:00:00Z',
        'series': {
          'user_registered': [
            {'day': '2026-07-02T00:00:00Z', 'n': 4},
          ],
          'landing_viewed': <Map<String, dynamic>>[],
        },
      });
      expect(ts.denseSeries('user_registered').map((c) => c.n), [0, 4]);
      expect(ts.denseSeries('landing_viewed').map((c) => c.n), [0, 0]);
    });
  });
}
