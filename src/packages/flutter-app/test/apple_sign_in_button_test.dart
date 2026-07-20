import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/services/auth_service.dart';
import 'package:travel_route_planner/services/auth_storage.dart';
import 'package:travel_route_planner/widgets/apple_sign_in_button.dart';

import 'support/l10n_test_app.dart';

/// AuthService with a scripted Apple availability answer.
class _FakeAuthService extends AuthService {
  final bool available;
  _FakeAuthService({required this.available}) : super(baseUrl: 'http://unused');

  @override
  Future<bool> appleSignInAvailable() async => available;
}

class _FakeAuthStorage extends AuthStorage {
  @override
  Future<String?> loadToken() async => null;

  @override
  Future<void> saveToken(String value) async {}

  @override
  Future<void> clearToken() async {}
}

Widget _wrap({required bool available}) {
  return ProviderScope(
    overrides: [
      authServiceProvider
          .overrideWithValue(_FakeAuthService(available: available)),
      authStorageProvider.overrideWithValue(_FakeAuthStorage()),
    ],
    child: localizedTestApp(
      home: const Scaffold(body: AppleSignInButton()),
    ),
  );
}

void main() {
  testWidgets('renders nothing when the backend has no Apple credentials',
      (tester) async {
    await tester.pumpWidget(_wrap(available: false));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Apple'), findsNothing);
  });

  testWidgets('shows the black HIG button when Apple sign-in is available',
      (tester) async {
    await tester.pumpWidget(_wrap(available: true));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.byIcon(Icons.apple), findsOneWidget);
  });
}
