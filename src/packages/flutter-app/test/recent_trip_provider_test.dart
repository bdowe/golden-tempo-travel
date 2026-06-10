import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travel_route_planner/providers/recent_trip_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('record then load round-trips the trip under the user-scoped key', () async {
    final writer = RecentTripNotifier('user-1');
    await writer.record('trip-42', 'Luxury Paris Weekend');

    final reader = RecentTripNotifier('user-1');
    await reader.load();
    expect(reader.state?.tripId, 'trip-42');
    expect(reader.state?.title, 'Luxury Paris Weekend');
  });

  test('recent trip is scoped per user', () async {
    final u1 = RecentTripNotifier('user-1');
    await u1.record('trip-42', 'Paris');

    final u2 = RecentTripNotifier('user-2');
    await u2.load();
    expect(u2.state, isNull);
  });

  test('anonymous (null userId) never records', () async {
    final anon = RecentTripNotifier(null);
    await anon.record('trip-42', 'Paris');
    expect(anon.state, isNull);

    await anon.load();
    expect(anon.state, isNull);
  });

  test('clearIfMatches clears only on a matching id', () async {
    final n = RecentTripNotifier('user-1');
    await n.record('trip-42', 'Paris');

    await n.clearIfMatches('other-trip');
    expect(n.state?.tripId, 'trip-42');

    await n.clearIfMatches('trip-42');
    expect(n.state, isNull);

    // The cleared value must not resurrect on reload.
    final reader = RecentTripNotifier('user-1');
    await reader.load();
    expect(reader.state, isNull);
  });
}
