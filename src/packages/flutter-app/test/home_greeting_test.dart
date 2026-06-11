import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/screens/home_screen.dart';

/// Auth notifier pinned to a fixed signed-in state, so the home screen can be
/// pumped without network or storage.
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
  Future<void> logout() async {}
}

UserModel _user(String displayName) => UserModel(
      id: 'user-1',
      email: 'test@example.com',
      displayName: displayName,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pumpHome(WidgetTester tester, UserModel? user) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('greetingForHour', () {
    test('morning until noon', () {
      expect(greetingForHour(0), 'Good morning');
      expect(greetingForHour(11), 'Good morning');
    });

    test('afternoon from noon until 5pm', () {
      expect(greetingForHour(12), 'Good afternoon');
      expect(greetingForHour(16), 'Good afternoon');
    });

    test('evening from 5pm', () {
      expect(greetingForHour(17), 'Good evening');
      expect(greetingForHour(23), 'Good evening');
    });
  });

  group('home greeting header', () {
    testWidgets('greets the user by first name only', (tester) async {
      await _pumpHome(tester, _user('Brian Dowe'));

      final greeting = greetingForHour(DateTime.now().hour);
      expect(find.text('$greeting, Brian'), findsOneWidget);
      expect(find.text('Where are we off to next?'), findsOneWidget);
    });

    testWidgets('falls back to a bare greeting when display name is empty',
        (tester) async {
      await _pumpHome(tester, _user(''));

      final greeting = greetingForHour(DateTime.now().hour);
      expect(find.text(greeting), findsOneWidget);
      expect(find.textContaining('$greeting,'), findsNothing);
    });
  });
}
