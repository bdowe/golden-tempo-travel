import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/screens/sso_callback_screen.dart';
import 'package:travel_route_planner/services/auth_service.dart';
import 'package:travel_route_planner/services/auth_storage.dart';

import 'support/l10n_test_app.dart';

final _testUser = UserModel(
  id: 'u1',
  email: 'sso@example.com',
  displayName: 'SSO Traveler',
  needsOnboarding: true,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// AuthService whose exchange is scripted per test.
class _FakeAuthService extends AuthService {
  final Future<AuthResponse> Function(String code) onExchange;
  String? exchangedCode;
  _FakeAuthService(this.onExchange) : super(baseUrl: 'http://unused');

  @override
  Future<AuthResponse> exchangeSsoCode(String code) {
    exchangedCode = code;
    return onExchange(code);
  }
}

/// In-memory AuthStorage that records the adopted token.
class _FakeAuthStorage extends AuthStorage {
  String? token;

  @override
  Future<String?> loadToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

Widget _wrap(_FakeAuthService service, _FakeAuthStorage storage, String code) {
  // The screen ends with pushNamedAndRemoveUntil('/'), so '/' must NOT be the
  // screen under test (a `home:` would make it so and loop the navigation
  // forever). Route the screen at /sso and mark '/' with a HOME sentinel.
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(service),
      authStorageProvider.overrideWithValue(storage),
    ],
    child: MaterialApp(
      localizationsDelegates: testLocalizationsDelegates,
      initialRoute: '/sso',
      onGenerateRoute: (settings) {
        if (settings.name == '/sso') {
          return MaterialPageRoute(
            builder: (_) => SsoCallbackScreen(code: code),
          );
        }
        return MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('HOME')),
        );
      },
    ),
  );
}

void main() {
  testWidgets('exchanges the code, adopts the session, and lands on /',
      (tester) async {
    final service = _FakeAuthService(
        (code) async => AuthResponse(user: _testUser, token: 'sso-session'));
    final storage = _FakeAuthStorage();

    await tester.pumpWidget(_wrap(service, storage, 'one-time-code'));
    await tester.pumpAndSettle();

    expect(service.exchangedCode, 'one-time-code');
    expect(storage.token, 'sso-session');
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('code "error" shows the cancelled message without exchanging',
      (tester) async {
    final service = _FakeAuthService((code) async => throw StateError('no'));
    final storage = _FakeAuthStorage();

    await tester.pumpWidget(_wrap(service, storage, 'error'));
    await tester.pumpAndSettle();

    expect(service.exchangedCode, isNull);
    expect(
      find.text('Sign-in was cancelled or failed. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Back to sign in'), findsOneWidget);
  });

  testWidgets('a failed exchange shows the expired message', (tester) async {
    final service = _FakeAuthService((code) async =>
        throw const AuthException(statusCode: 404, message: 'expired'));
    final storage = _FakeAuthStorage();

    await tester.pumpWidget(_wrap(service, storage, 'stale-code'));
    await tester.pumpAndSettle();

    expect(storage.token, isNull);
    expect(
      find.text('This sign-in link expired. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Back to sign in'), findsOneWidget);
  });
}
