import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trip_finding.dart';
import '../services/trip_review_api_service.dart';
import 'api_client_provider.dart';

final tripReviewApiServiceProvider = Provider<TripReviewApiService>((ref) {
  return TripReviewApiService(ref.watch(apiClientProvider));
});

/// Key for [tripReviewProvider]: a trip id plus the opt-in opening-hours flag.
/// The flag participates in equality so flipping it fetches a distinct result
/// (and keeps the base, hours-off review cached alongside).
class TripReviewKey {
  final String tripId;
  final bool checkHours;

  const TripReviewKey(this.tripId, {this.checkHours = false});

  @override
  bool operator ==(Object other) =>
      other is TripReviewKey &&
      other.tripId == tripId &&
      other.checkHours == checkHours;

  @override
  int get hashCode => Object.hash(tripId, checkHours);
}

/// A trip's health review, keyed by (trip id, check-hours). Mirrors
/// [checklistProvider]: refreshable by invalidating the family key. The
/// hours-on variant is fetched lazily when the section flips the flag.
final tripReviewProvider =
    FutureProvider.family<List<TripFinding>, TripReviewKey>((ref, key) async {
  return ref
      .watch(tripReviewApiServiceProvider)
      .getReview(key.tripId, checkHours: key.checkHours);
});
