import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/screens/auth_screen.dart';
import 'package:travel_route_planner/services/auth_service.dart';
import 'package:travel_route_planner/services/auth_storage.dart';

import 'support/l10n_test_app.dart';

/// Records login/register calls; Google SSO reports unavailable so the
/// button stays hidden.
class _FakeAuthService extends AuthService {
  final List<(String, String)> loginCalls = [];
  final List<(String, String)> registerCalls = [];

  _FakeAuthService() : super(baseUrl: 'http://unused');

  static final _user = UserModel(
    id: 'u1',
    email: 'brian@example.com',
    displayName: 'Brian',
    createdAt: DateTime.utc(2026, 1, 1),
  );

  @override
  Future<AuthResponse> login(String email, String password) async {
    loginCalls.add((email, password));
    return AuthResponse(user: _user, token: 'tok');
  }

  @override
  Future<AuthResponse> register(String email, String password,
      {String? displayName}) async {
    registerCalls.add((email, password));
    return AuthResponse(user: _user, token: 'tok');
  }

  @override
  Future<bool> googleSignInAvailable() async => false;
}

class _FakeAuthStorage extends AuthStorage {
  String? token;

  @override
  Future<String?> loadToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

Widget _wrap(_FakeAuthService service) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(service),
      authStorageProvider.overrideWithValue(_FakeAuthStorage()),
    ],
    child: localizedTestApp(home: const AuthScreen()),
  );
}

Finder _fieldByLabel(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextFormField),
    );

void main() {
  testWidgets('password-manager style double fill auto-submits sign-in',
      (tester) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    // Both fields jump from empty to a full value back-to-back, like an
    // extension fill.
    await tester.enterText(_fieldByLabel('Email'), 'brian@example.com');
    await tester.enterText(_fieldByLabel('Password'), 'hunter2hunter2');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(service.loginCalls, [('brian@example.com', 'hunter2hunter2')]);
  });

  testWidgets('human-paced entry does not auto-submit', (tester) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    await tester.enterText(_fieldByLabel('Email'), 'brian@example.com');
    // The fill window compares wall-clock timestamps, so let real time pass
    // (runAsync escapes the fake-async zone), well outside the 500ms window.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)));
    await tester.enterText(_fieldByLabel('Password'), 'hunter2hunter2');
    await tester.pump(const Duration(seconds: 1));

    expect(service.loginCalls, isEmpty);
  });

  testWidgets('sign-up mode never auto-submits', (tester) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(_wrap(service));
    await tester.pump();

    await tester.ensureVisible(find.text("Don't have an account? Sign up"));
    await tester.tap(find.text("Don't have an account? Sign up"));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldByLabel('Email'), 'brian@example.com');
    await tester.enterText(_fieldByLabel('Password'), 'hunter2hunter2');
    await tester.pump(const Duration(seconds: 1));

    expect(service.registerCalls, isEmpty);
    expect(service.loginCalls, isEmpty);
  });
}
