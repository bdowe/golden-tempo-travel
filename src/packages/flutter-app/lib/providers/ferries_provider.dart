import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ferry_option.dart';
import '../services/ferry_api_service.dart';
import 'api_client_provider.dart';

final ferryApiServiceProvider = Provider<FerryApiService>((ref) {
  return FerryApiService(ref.watch(apiClientProvider));
});

/// Identifies one ferry lookup: a route and (optional) date. Used as the family
/// key so each island-hop leg caches its own result.
class FerryQuery {
  final String origin;
  final String destination;
  final String? date; // YYYY-MM-DD

  const FerryQuery({
    required this.origin,
    required this.destination,
    this.date,
  });

  @override
  bool operator ==(Object other) =>
      other is FerryQuery &&
      other.origin == origin &&
      other.destination == destination &&
      other.date == date;

  @override
  int get hashCode => Object.hash(origin, destination, date);
}

/// Ferry options for a route. Returns [] for incomplete queries so callers can
/// render nothing without special-casing.
final ferriesByRouteProvider =
    FutureProvider.family<List<FerryOption>, FerryQuery>((ref, query) async {
  if (query.origin.trim().isEmpty || query.destination.trim().isEmpty) {
    return [];
  }
  final service = ref.watch(ferryApiServiceProvider);
  return service.searchFerries(
    query.origin.trim(),
    query.destination.trim(),
    date: query.date,
  );
});
