import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:travel_route_planner/models/budget.dart';
import 'package:travel_route_planner/models/expense.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/budget_api_service.dart';
import 'package:travel_route_planner/providers/budget_provider.dart';
import 'package:travel_route_planner/utils/money_format.dart';
import 'package:travel_route_planner/widgets/budget_section.dart';

/// A stateful fake: it holds the target/currency + the expense list so
/// invalidate-after-mutate reflects the change, derives spent/remaining exactly
/// like the server, and records which network methods were called.
class _FakeBudgetApiService extends BudgetApiService {
  final List<Expense> expenses;
  double? targetAmount;
  String currency;

  final List<Map<String, dynamic>> patches = [];
  final List<Map<String, dynamic>> puts = [];
  int addCount = 0;
  int deleteCount = 0;

  _FakeBudgetApiService(this.expenses, {this.targetAmount, this.currency = 'USD'})
      : super(ApiClient(baseUrl: 'http://test'));

  double get _spent => expenses.fold<double>(0, (s, e) => s + e.amount);

  @override
  Future<Budget> getBudget(String tripId) async => Budget(
        targetAmount: targetAmount,
        currency: currency,
        spent: _spent,
        remaining: targetAmount == null ? null : targetAmount! - _spent,
      );

  @override
  Future<List<Expense>> listExpenses(String tripId) async =>
      List.of(expenses); // snapshot

  @override
  Future<Budget> upsertBudget(String tripId,
      {double? targetAmount, String currency = 'USD'}) async {
    puts.add({'target_amount': targetAmount, 'currency': currency});
    this.targetAmount = targetAmount;
    this.currency = currency;
    return getBudget(tripId);
  }

  @override
  Future<Expense> addExpense(String tripId,
      {required String category,
      required String label,
      required double amount}) async {
    addCount++;
    final e = Expense(
        id: 'new-$addCount',
        category: category,
        label: label,
        amount: amount);
    expenses.add(e);
    return e;
  }

  @override
  Future<Expense> updateExpense(
      String tripId, String expenseId, Map<String, dynamic> body) async {
    patches.add({'id': expenseId, ...body});
    final idx = expenses.indexWhere((e) => e.id == expenseId);
    if (idx >= 0) {
      expenses[idx] = expenses[idx].copyWith(
        category: body['category'] as String?,
        label: body['label'] as String?,
        amount: (body['amount'] as num?)?.toDouble(),
      );
      return expenses[idx];
    }
    throw Exception('not found');
  }

  @override
  Future<void> deleteExpense(String tripId, String expenseId) async {
    deleteCount++;
    expenses.removeWhere((e) => e.id == expenseId);
  }
}

Expense _exp(String id, String category, String label, double amount) =>
    Expense(id: id, category: category, label: label, amount: amount);

Future<_FakeBudgetApiService> _pump(
  WidgetTester tester,
  List<Expense> expenses, {
  double? targetAmount,
  String currency = 'USD',
  bool canEdit = true,
  bool isOffline = false,
}) async {
  final fake = _FakeBudgetApiService(expenses,
      targetAmount: targetAmount, currency: currency);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        budgetApiServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BudgetSection(
                tripId: 't1', canEdit: canEdit, isOffline: isOffline),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets(
      'renders expenses grouped with subtotals, a running total, and remaining',
      (tester) async {
    await _pump(
      tester,
      [
        _exp('a', 'flights', 'JFK→CDG', 400),
        _exp('b', 'food', 'Dinner', 60),
        _exp('c', 'food', 'Lunch', 40),
      ],
      targetAmount: 1000,
      currency: 'EUR',
    );

    expect(find.text('Budget'), findsOneWidget);
    // Category group headers.
    expect(find.text('Flights'), findsOneWidget);
    expect(find.text('Food'), findsOneWidget);
    // Flights subtotal = 400, Food subtotal = 100 (both in EUR).
    expect(find.text(formatMoney(400, 'EUR')), findsWidgets);
    expect(find.text(formatMoney(100, 'EUR')), findsOneWidget);
    // Running total = 500 spent.
    expect(find.text('Total spent'), findsOneWidget);
    expect(find.text(formatMoney(500, 'EUR')), findsWidgets);
    // Remaining = 1000 - 500 = 500.
    expect(find.text('Remaining'), findsOneWidget);
    // Pill shows spent / target.
    expect(
        find.text('${formatMoney(500, 'EUR')} / ${formatMoney(1000, 'EUR')}'),
        findsOneWidget);
  });

  testWidgets('adding an expense posts to the service', (tester) async {
    final fake = await _pump(tester, [_exp('a', 'food', 'Lunch', 20)]);

    await tester.enterText(find.byType(TextField).first, 'Taxi');
    await tester.enterText(find.byType(TextField).last, '15');
    await tester.tap(find.byTooltip('Add expense'));
    await tester.pumpAndSettle();

    expect(fake.addCount, 1);
    expect(find.text('Taxi'), findsOneWidget);
  });

  testWidgets('editing an expense calls PATCH', (tester) async {
    final fake = await _pump(tester, [_exp('a', 'food', 'Lunch', 20)]);

    await tester.tap(find.byTooltip('Expense options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Lunch'), 'Brunch');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.patches, isNotEmpty);
    expect(fake.patches.first['id'], 'a');
    expect(fake.patches.first['label'], 'Brunch');
  });

  testWidgets('setting a target calls PUT', (tester) async {
    final fake = await _pump(tester, [_exp('a', 'food', 'Lunch', 20)]);

    // Tap the target control (shows the "no target" hint text).
    await tester.tap(find.text('No target set — tracking spend only'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Leave blank for none'), '800');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.puts, isNotEmpty);
    expect(fake.puts.first['target_amount'], 800);
    expect(fake.puts.first['currency'], 'USD');
  });

  testWidgets('empty state shows the hint and an add field', (tester) async {
    await _pump(tester, []);

    expect(find.text('No budget yet'), findsOneWidget);
    expect(find.textContaining('track your spending'), findsOneWidget);
    // The add affordance is still available for the editor.
    expect(find.byTooltip('Add expense'), findsOneWidget);
  });

  testWidgets('viewer with no expenses and no target renders nothing',
      (tester) async {
    await _pump(tester, [], canEdit: false);

    expect(find.text('Budget'), findsNothing);
    expect(find.byTooltip('Add expense'), findsNothing);
  });

  testWidgets('viewer sees amounts but no mutation affordances',
      (tester) async {
    await _pump(tester, [_exp('a', 'food', 'Lunch', 20)],
        targetAmount: 100, canEdit: false);

    // The section renders with its data...
    expect(find.text('Budget'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    // ...but no add row, per-expense menu, or target control.
    expect(find.byTooltip('Add expense'), findsNothing);
    expect(find.byTooltip('Expense options'), findsNothing);
    expect(find.text('No target set — tracking spend only'), findsNothing);
  });

  testWidgets('offline disables the add affordance', (tester) async {
    await _pump(tester, [_exp('a', 'food', 'Lunch', 20)], isOffline: true);

    final addButton =
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add));
    expect(addButton.onPressed, isNull);
  });
}
