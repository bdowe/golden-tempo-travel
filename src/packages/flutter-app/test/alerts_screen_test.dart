import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/price_alert.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/alerts_provider.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/screens/alerts_screen.dart';
import 'package:travel_route_planner/services/alerts_api_service.dart';
import 'package:travel_route_planner/services/api_client.dart';

class _FakeAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  _FakeAuthNotifier(UserModel? user)
      : super(AuthState(user: user, initialized: true));

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
}

class _FakeAlertsApiService extends AlertsApiService {
  final List<PriceAlert> alerts;
  final List<String> patched = [];
  _FakeAlertsApiService(this.alerts)
      : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<List<PriceAlert>> list() async => alerts;

  @override
  Future<PriceAlert> patch(String id, Map<String, dynamic> body) async {
    patched.add('$id:${body['status']}');
    final a = alerts.firstWhere((a) => a.id == id);
    return PriceAlert(
      id: a.id,
      origin: a.origin,
      destination: a.destination,
      departDate: a.departDate,
      status: body['status'] as String,
      targetPrice: a.targetPrice,
      currency: a.currency,
    );
  }
}

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
}) =>
    PriceAlert(
      id: id,
      origin: 'BOS',
      destination: 'CDG',
      departDate: '2026-09-01',
      targetPrice: target,
      currency: 'USD',
      lastCheckedPrice: 498,
      status: status,
      lastNotifiedAt: lastNotifiedAt,
    );

Future<_FakeAlertsApiService> _pump(
  WidgetTester tester, {
  List<PriceAlert> alerts = const [],
  bool signedIn = true,
}) async {
  final service = _FakeAlertsApiService(alerts);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider
            .overrideWith((ref) => _FakeAuthNotifier(signedIn ? _user() : null)),
        alertsApiServiceProvider.overrideWithValue(service),
      ],
      child: const MaterialApp(home: AlertsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('signed out shows sign-in prompt', (tester) async {
    await _pump(tester, signedIn: false);
    expect(find.text('Sign in to watch fares'), findsOneWidget);
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
    expect(find.textContaining('target USD 450'), findsOneWidget);
    expect(find.textContaining('Last seen USD 498'), findsNWidgets(4));
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
