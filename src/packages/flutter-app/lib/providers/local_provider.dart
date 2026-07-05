import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/local_recommendation.dart';
import '../models/local_guide.dart';
import '../services/local_api_service.dart';
import 'api_client_provider.dart';

final localApiServiceProvider = Provider<LocalApiService>((ref) {
  return LocalApiService(ref.watch(apiClientProvider));
});

/// Published local recommendations for a city — keyed by city so each city group
/// in a trip caches its own results. Returns [] for a blank city.
final localRecsByCityProvider =
    FutureProvider.family<List<LocalRecommendation>, String>((ref, city) async {
  if (city.trim().isEmpty) return [];
  final service = ref.watch(localApiServiceProvider);
  return service.searchRecommendations(city.trim());
});

/// Published narrative guides for a city.
final localGuidesByCityProvider =
    FutureProvider.family<List<LocalGuide>, String>((ref, city) async {
  if (city.trim().isEmpty) return [];
  final service = ref.watch(localApiServiceProvider);
  return service.guides(city.trim());
});
