import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/services/auth_service.dart';
import 'package:travel_route_planner/services/auth_storage.dart';
import 'package:travel_route_planner/widgets/google_sign_in_button.dart';

/// AuthService with a scripted availability answer.
class _FakeAuthService extends AuthService {
  final bool available;
  _FakeAuthService({required this.available}) : super(baseUrl: 'http://unused');

  @override
  Future<bool> googleSignInAvailable() async => available;
}

/// In-memory AuthStorage so the auth provider never touches secure storage.
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
      authServiceProvider.overrideWithValue(_FakeAuthService(available: available)),
      authStorageProvider.overrideWithValue(_FakeAuthStorage()),
    ],
    child: const MaterialApp(
      home: Scaffold(body: GoogleSignInButton()),
    ),
  );
}

void main() {
  testWidgets('renders nothing when the backend has no Google OAuth client',
      (tester) async {
    await tester.pumpWidget(_wrap(available: false));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('shows the button when Google sign-in is available',
      (tester) async {
    await tester.pumpWidget(_wrap(available: true));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
  });
}
