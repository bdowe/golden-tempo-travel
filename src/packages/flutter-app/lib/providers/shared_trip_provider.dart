import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shared_trip.dart';
import 'trips_provider.dart';

/// Public shared-trip lookup by token. FutureProvider.family so each opened
/// link caches independently; works signed-out.
final sharedTripProvider =
    FutureProvider.family<SharedTrip, String>((ref, token) {
  return ref.read(tripsApiServiceProvider).getSharedTrip(token);
});
