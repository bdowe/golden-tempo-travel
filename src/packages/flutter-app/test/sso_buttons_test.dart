import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/services/auth_service.dart';
import 'package:travel_route_planner/services/auth_storage.dart';
import 'package:travel_route_planner/widgets/sso_buttons.dart';

import 'support/l10n_test_app.dart';

/// AuthService with scripted availability per provider.
class _FakeAuthService extends AuthService {
  final bool google;
  final bool apple;
  _FakeAuthService({required this.google, required this.apple})
      : super(baseUrl: 'http://unused');

  @override
  Future<bool> googleSignInAvailable() async => google;

  @override
  Future<bool> appleSignInAvailable() async => apple;
}

class _FakeAuthStorage extends AuthStorage {
  @override
  Future<String?> loadToken() async => null;

  @override
  Future<void> saveToken(String value) async {}

  @override
  Future<void> clearToken() async {}
}

Widget _wrap({required bool google, required bool apple, Locale? locale}) {
  return ProviderScope(
    overrides: [
      authServiceProvider
          .overrideWithValue(_FakeAuthService(google: google, apple: apple)),
      authStorageProvider.overrideWithValue(_FakeAuthStorage()),
    ],
    child: localizedTestApp(
      home: const Scaffold(body: SsoButtons()),
      locale: locale,
    ),
  );
}

void main() {
  testWidgets('renders nothing when no provider is configured',
      (tester) async {
    await tester.pumpWidget(_wrap(google: false, apple: false));
    await tester.pumpAndSettle();

    expect(find.text('or'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);
  });

  testWidgets('one divider and one button when only Google is available',
      (tester) async {
    await tester.pumpWidget(_wrap(google: true, apple: false));
    await tester.pumpAndSettle();

    expect(find.text('or'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
  });

  testWidgets('one divider and one button when only Apple is available',
      (tester) async {
    await tester.pumpWidget(_wrap(google: false, apple: true));
    await tester.pumpAndSettle();

    expect(find.text('or'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('both buttons under a single divider when both are available',
      (tester) async {
    await tester.pumpWidget(_wrap(google: true, apple: true));
    await tester.pumpAndSettle();

    expect(find.text('or'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  // Spanish ships ahead of enablement (specs/i18n-spanish): the translations
  // are complete and rendering long before `es` reaches kSupportedLocales, so
  // a regression in the .arb files fails here rather than in PR 7.
  testWidgets('renders Spanish copy under an es locale', (tester) async {
    await tester.pumpWidget(
        _wrap(google: true, apple: true, locale: const Locale('es')));
    await tester.pumpAndSettle();

    expect(find.text('Continuar con Google'), findsOneWidget);
    expect(find.text('Continuar con Apple'), findsOneWidget);
    expect(find.text('o'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });
}
