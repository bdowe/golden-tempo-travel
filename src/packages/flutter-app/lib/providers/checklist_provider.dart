import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/checklist_item.dart';
import '../services/checklist_api_service.dart';
import 'api_client_provider.dart';

final checklistApiServiceProvider = Provider<ChecklistApiService>((ref) {
  return ChecklistApiService(ref.watch(apiClientProvider));
});

/// A trip's packing & prep checklist, keyed by trip id. Mutations invalidate
/// this provider to refetch; `.when(skipLoadingOnReload)` (the default) keeps
/// the current list on screen during the refresh so toggles don't flash.
final checklistProvider =
    FutureProvider.family<List<ChecklistItem>, String>((ref, tripId) async {
  return ref.watch(checklistApiServiceProvider).list(tripId);
});
