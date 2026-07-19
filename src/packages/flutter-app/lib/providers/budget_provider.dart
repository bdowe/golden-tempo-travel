import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/budget.dart';
import '../models/expense.dart';
import '../services/budget_api_service.dart';
import 'api_client_provider.dart';

final budgetApiServiceProvider = Provider<BudgetApiService>((ref) {
  return BudgetApiService(ref.watch(apiClientProvider));
});

/// A trip's budget (target + currency + derived spent/remaining), keyed by trip
/// id. Mutations invalidate this provider to refetch. `.when(skipLoadingOnReload)`
/// (the default) keeps the current values on screen during the refresh.
final budgetProvider =
    FutureProvider.family<Budget, String>((ref, tripId) async {
  return ref.watch(budgetApiServiceProvider).getBudget(tripId);
});

/// A trip's expense line-items, keyed by trip id. Invalidated alongside
/// [budgetProvider] on every mutation.
final expensesProvider =
    FutureProvider.family<List<Expense>, String>((ref, tripId) async {
  return ref.watch(budgetApiServiceProvider).listExpenses(tripId);
});
