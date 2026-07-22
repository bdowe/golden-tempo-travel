import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/plan_message.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/providers/notifications_provider.dart';
import 'package:travel_route_planner/providers/plan_provider.dart';
import 'package:travel_route_planner/screens/agent_screen.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/plan_service.dart';

import 'support/l10n_test_app.dart';

/// The itinerary banner's CTA rules: a saved trip gets exactly one action
/// ("View trip" — the trip screen carries the itinerary, bookings, and map);
/// an anonymous completion keeps the route-planner fallback, its only action.

class _SeededPlanNotifier extends PlanNotifier {
  _SeededPlanNotifier(PlanState seeded)
      : super(PlanService('http://unused'), ApiClient()) {
    state = seeded;
  }
}

class _FakeAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  _FakeAuthNotifier() : super(AuthState(user: null, initialized: true));

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

/// A finished conversation: the banner only renders alongside a non-empty
/// transcript (an empty one shows the suggestion empty-state instead), so the
/// seed must include committed messages.
PlanState _completedState({String? tripId}) => PlanState(
      messages: [
        PlanMessage(role: MessageRole.user, content: 'plan athens'),
        PlanMessage(role: MessageRole.assistant, content: 'Here is your plan.'),
      ],
      completedLocations: const [
        {'name': 'Acropolis'},
        {'name': 'Plaka'},
      ],
      completedSummary: 'Two days in Athens',
      savedTripId: tripId,
    );

Future<void> _pumpAgentScreen(WidgetTester tester, PlanState seeded) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planProvider.overrideWith((ref) => _SeededPlanNotifier(seeded)),
        authProvider.overrideWith((ref) => _FakeAuthNotifier()),
        notificationsUnreadCountProvider.overrideWith((ref) async => 0),
      ],
      child: localizedTestApp(home: const AgentScreen()),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('saved trip shows a single View trip CTA',
      (WidgetTester tester) async {
    await _pumpAgentScreen(tester, _completedState(tripId: 'trip-1'));

    expect(find.text('View trip'), findsOneWidget);
    expect(find.text('Load into route planner'), findsNothing);
    expect(find.text('Load into Planner'), findsNothing);
  });

  testWidgets('anonymous completion keeps the route-planner fallback',
      (WidgetTester tester) async {
    await _pumpAgentScreen(tester, _completedState());

    expect(find.text('Load into Planner'), findsOneWidget);
    expect(find.text('View trip'), findsNothing);
  });
}
