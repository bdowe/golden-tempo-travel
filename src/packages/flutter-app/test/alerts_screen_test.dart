import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/alert_event.dart';
import 'package:travel_route_planner/models/price_alert.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/alerts_provider.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/screens/alerts_screen.dart';
import 'package:travel_route_planner/screens/auth_screen.dart';
import 'package:travel_route_planner/screens/notification_center_screen.dart';
import 'package:travel_route_planner/services/alerts_api_service.dart';
import 'package:travel_route_planner/services/api_client.dart';

class _FakeAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  _FakeAuthNotifier(UserModel? user)
      : super(AuthState(user: user, initialized: true));

  /// Simulates a session arriving (e.g. sign-in completing on the pushed
  /// AuthScreen) without driving the auth UI.
  void signInAs(UserModel user) {
    state = AuthState(user: user, initialized: true);
  }

  @override
  Future<bool> login(String email, String password) async => false;

  @override
  Future<bool> register(String email, String password,
          {String? displayName}) async =>
      false;

  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> signOutLocally() async {}

  @override
  void setUser(UserModel user) {}

  @override
  Future<void> adoptSession(String token, UserModel user) async {}

}

class _FakeAlertsApiService extends AlertsApiService {
  final List<PriceAlert> alerts;
  final List<AlertEvent> events;
  final int unread;
  final List<String> patched = [];
  bool markReadCalled = false;
  _FakeAlertsApiService(this.alerts, {this.events = const [], this.unread = 0})
      : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<List<PriceAlert>> list() async => alerts;

  @override
  Future<PriceAlert> patch(String id, Map<String, dynamic> body) async {
    final a = alerts.firstWhere((a) => a.id == id);
    if (body.containsKey('status')) patched.add('$id:${body['status']}');
    if (body.containsKey('target_price')) {
      patched.add('$id:target=${body['target_price']}');
    }
    return PriceAlert(
      id: a.id,
      origin: a.origin,
      destination: a.destination,
      departDate: a.departDate,
      status: (body['status'] as String?) ?? a.status,
      targetPrice: (body['target_price'] as double?) ?? a.targetPrice,
      currency: a.currency,
    );
  }

  @override
  Future<List<AlertEvent>> listAlertEvents({int limit = 50}) async => events;

  @override
  Future<void> markAlertEventsRead() async {
    markReadCalled = true;
  }

  @override
  Future<int> alertUnreadCount() async => unread;
}

AlertEvent _event({
  String id = 'e1',
  String origin = 'BOS',
  String destination = 'CDG',
  double price = 412,
  double? previousPrice = 498,
  String occurredAt = '2026-07-15T12:00:00Z',
  String? readAt,
}) =>
    AlertEvent(
      id: id,
      alertId: 'a1',
      price: price,
      currency: 'USD',
      previousPrice: previousPrice,
      occurredAt: occurredAt,
      readAt: readAt,
      origin: origin,
      destination: destination,
      departDate: '2026-09-01',
      alertStatus: 'active',
    );

UserModel _user() => UserModel(
      id: 'user-1',
      email: 'test@example.com',
      displayName: 'Test',
      createdAt: DateTime(2026, 1, 1),
    );

PriceAlert _alert({
  String id = 'a1',
  String status = 'active',
  double? target,
  String? lastNotifiedAt,
  double? baselinePrice,
  double? lastCheckedPrice = 498,
  String? lastCheckedAt,
}) =>
    PriceAlert(
      id: id,
      origin: 'BOS',
      destination: 'CDG',
      departDate: '2026-09-01',
      targetPrice: target,
      currency: 'USD',
      baselinePrice: baselinePrice,
      lastCheckedPrice: lastCheckedPrice,
      lastCheckedAt: lastCheckedAt,
      status: status,
      lastNotifiedAt: lastNotifiedAt,
    );

Future<_FakeAlertsApiService> _pump(
  WidgetTester tester, {
  List<PriceAlert> alerts = const [],
  bool signedIn = true,
  _FakeAuthNotifier? auth,
  int unread = 0,
  List<Override> extraOverrides = const [],
}) async {
  final service = _FakeAlertsApiService(alerts, unread: unread);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(
            (ref) => auth ?? _FakeAuthNotifier(signedIn ? _user() : null)),
        alertsApiServiceProvider.overrideWithValue(service),
        ...extraOverrides,
      ],
      child: const MaterialApp(home: AlertsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

Future<_FakeAlertsApiService> _pumpCenter(
  WidgetTester tester, {
  List<AlertEvent> events = const [],
  int unread = 0,
}) async {
  final service = _FakeAlertsApiService([], events: events, unread: unread);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(_user())),
        alertsApiServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: NotificationCenterScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('signed out shows sign-in prompt with a working action',
      (tester) async {
    await _pump(tester, signedIn: false);
    expect(find.text('Sign in to watch fares'), findsOneWidget);

    // The email deep link lands here signed out — the prompt must offer a
    // route into auth, not a dead end.
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
  });

  testWidgets('deep link lands on loaded alerts once the session arrives',
      (tester) async {
    final auth = _FakeAuthNotifier(null);
    await _pump(tester, alerts: [_alert(id: 'a1')], auth: auth);
    expect(find.text('Sign in to watch fares'), findsOneWidget);

    auth.signInAs(_user());
    await tester.pumpAndSettle();

    expect(find.text('Sign in to watch fares'), findsNothing);
    expect(find.text('BOS → CDG'), findsOneWidget);
  });

  testWidgets('empty list shows how-to empty state', (tester) async {
    await _pump(tester);
    expect(find.text('No alerts yet'), findsOneWidget);
  });

  testWidgets('renders alert states', (tester) async {
    await _pump(tester, alerts: [
      _alert(id: 'a1', target: 450),
      _alert(id: 'a2', lastNotifiedAt: '2026-07-01T00:00:00Z'),
      _alert(id: 'a3', status: 'paused'),
      _alert(id: 'a4', status: 'expired'),
    ]);
    expect(find.text('BOS → CDG'), findsNWidgets(4));
    expect(find.text('Watching'), findsOneWidget);
    expect(find.text('Price dropped'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Expired'), findsOneWidget);
    expect(find.textContaining('target \$450'), findsOneWidget);
    expect(find.textContaining('Last seen \$498'), findsNWidgets(4));
  });

  testWidgets('pause action patches the alert', (tester) async {
    final service = await _pump(tester, alerts: [_alert(id: 'a1')]);

    await tester.tap(find.byTooltip('Alert actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(service.patched, ['a1:paused']);
    expect(find.text('Paused'), findsOneWidget);
  });

  testWidgets('notification center renders drops newest-first with delta',
      (tester) async {
    await _pumpCenter(tester, events: [
      _event(
        id: 'e-new',
        origin: 'JFK',
        destination: 'LAX',
        price: 210,
        previousPrice: 260,
        occurredAt: '2026-07-16T12:00:00Z',
      ),
      _event(
        id: 'e-old',
        origin: 'BOS',
        destination: 'CDG',
        price: 412,
        previousPrice: 498,
        occurredAt: '2026-07-10T12:00:00Z',
      ),
    ]);

    // Drop line uses price + previous_price.
    expect(find.textContaining('\$412, down from \$498'), findsOneWidget);
    expect(find.textContaining('\$210, down from \$260'), findsOneWidget);

    // Newest first: the JFK→LAX row (newer occurred_at) sits above BOS→CDG.
    final newerY = tester.getTopLeft(find.text('JFK → LAX')).dy;
    final olderY = tester.getTopLeft(find.text('BOS → CDG')).dy;
    expect(newerY, lessThan(olderY));
  });

  testWidgets('event with no previous price shows just the new price',
      (tester) async {
    await _pumpCenter(tester, events: [_event(previousPrice: null, price: 300)]);
    expect(find.textContaining('\$300'), findsOneWidget);
    expect(find.textContaining('down from'), findsNothing);
  });

  testWidgets('empty center shows the how-to empty state', (tester) async {
    await _pumpCenter(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets('opening the center marks all events read', (tester) async {
    final service = await _pumpCenter(tester, events: [_event()], unread: 3);
    expect(service.markReadCalled, isTrue);
  });

  testWidgets('unread badge reflects the provider', (tester) async {
    await _pump(
      tester,
      alerts: [_alert()],
      extraOverrides: [
        alertUnreadCountProvider.overrideWith((ref) async => 4),
      ],
    );
    // The bell in the app bar carries the badge count.
    expect(find.widgetWithText(Badge, '4'), findsOneWidget);
  });

  testWidgets('unread badge is hidden at zero', (tester) async {
    await _pump(
      tester,
      alerts: [_alert()],
      extraOverrides: [
        alertUnreadCountProvider.overrideWith((ref) async => 0),
      ],
    );
    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('card renders baseline delta and check freshness',
      (tester) async {
    await _pump(tester, alerts: [
      _alert(
        baselinePrice: 498,
        lastCheckedPrice: 412,
        lastCheckedAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
      ),
    ]);
    expect(find.textContaining('Down \$86 from when you started watching'),
        findsOneWidget);
    expect(find.textContaining('Checked 2 hours ago'), findsOneWidget);
  });

  testWidgets('edit-target dialog patches the alert', (tester) async {
    final service = await _pump(tester, alerts: [_alert(target: 450)]);

    await tester.tap(find.byTooltip('Alert actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit target price'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '399');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(service.patched, contains('a1:target=399.0'));
  });

  test('model round-trips snake_case JSON', () {
    final json = {
      'id': 'a1',
      'origin': 'BOS',
      'destination': 'CDG',
      'depart_date': '2026-09-01',
      'return_date': null,
      'cabin_class': 'economy',
      'adults': 2,
      'target_price': 450.0,
      'currency': 'USD',
      'last_checked_price': 498.0,
      'last_checked_at': '2026-07-05T12:00:00Z',
      'last_notified_price': null,
      'last_notified_at': null,
      'status': 'active',
      'trip_id': null,
      'created_at': '2026-07-05T10:00:00Z',
    };
    final alert = PriceAlert.fromJson(json);
    expect(alert.origin, 'BOS');
    expect(alert.adults, 2);
    expect(alert.targetPrice, 450.0);
    expect(alert.isAnyDrop, false);
    expect(alert.hasTriggered, false);
    expect(alert.toJson()['depart_date'], '2026-09-01');
  });
}
