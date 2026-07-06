import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trip_cache.dart';
import 'auth_provider.dart';

/// Per-user offline trip cache. Rebuilds on sign-in/out so each user only
/// ever reads their own cached trips (same pattern as [recentTripProvider]).
final tripCacheProvider = Provider<TripCache>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  return TripCache(userId);
});
