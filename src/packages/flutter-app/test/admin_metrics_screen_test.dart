import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/admin_metrics.dart';
import 'package:travel_route_planner/providers/admin_metrics_provider.dart';
import 'package:travel_route_planner/screens/admin_metrics_screen.dart';

void main() {
  testWidgets('renders funnel, AI, and alert tiles from metrics',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const metrics = AdminMetrics(
      days: 30,
      signups: 42,
      activatedSignups: 21,
      activationRate: 0.5,
      tripsCreated: 30,
      attachRate: 0.15,
      bookingClicks: 12,
      clicksByProvider: {'booking': 8, 'airbnb': 4},
      secondTripRetention: 7,
      activeUsers: 60,
      planSessions: 100,
      planSessionsAnonymous: 40,
      agentLoopCapHits: 2,
      planInputTokens: 1500000,
      planOutputTokens: 250000,
      planCacheReadTokens: 900000,
      estClaudeCostUsd: 12.5,
      estCogsPerActiveUser: 0.21,
      alertsCreated: 5,
      alertsTriggered: 1,
      freeCapWouldHits: {'plan_runs': 3, 'active_trips': 1},
      freeCapUsersAffected: {'plan_runs': 2, 'active_trips': 1},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminMetricsProvider(30).overrideWith((ref) async => metrics),
        ],
        child: const MaterialApp(home: AdminMetricsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget); // signups
    expect(find.text('50.0%'), findsOneWidget); // activation rate
    expect(find.text('15.0%'), findsOneWidget); // attach rate
    expect(find.text('40 anonymous'), findsOneWidget);
    expect(find.text('1.5M'), findsOneWidget); // tokens in
    expect(find.text('900.0k from cache'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // second-trip retention
    expect(find.text('≥2 trips ≥7 days apart'), findsOneWidget);
    expect(find.text('60'), findsOneWidget); // MAU
    expect(find.text('\$0.21'), findsOneWidget); // est. cost / active user
    expect(find.text('Claude only, estimate'), findsOneWidget);
    expect(find.text('Agent loop cap hits'), findsOneWidget);
    expect(find.text('Would hit plan cap'), findsOneWidget);
    expect(find.text('2 users affected'), findsOneWidget); // plan_runs cohort
    expect(find.text('Would hit trip cap'), findsOneWidget);
    expect(
        find.text('1 users affected'), findsOneWidget); // active_trips cohort
    expect(find.text('Clicks by provider'), findsOneWidget);
    expect(find.text('booking'), findsOneWidget);
    expect(find.text('Price alerts'), findsOneWidget);
  });

  testWidgets('error state offers retry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminMetricsProvider(30)
              .overrideWith((ref) async => throw Exception('403')),
        ],
        child: const MaterialApp(home: AdminMetricsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load metrics'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
