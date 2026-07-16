import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trip.dart';
import '../utils/trip_days.dart';
import 'trips_provider.dart';

/// The trip from [trips] that is happening on [now]'s device-local calendar
/// date, or null when none is. Liveness reuses [tripDayOn] (specs/today-mode):
/// dated, start <= today <= end (end-day inclusive; a missing end date means
/// the trip never ends once started). No status filter — a draft you're on is
/// still the trip you're on.
///
/// When several trips are live at once, the one that started most recently
/// wins (it's the leg you're actually living); trips with the same start date
/// tie-break by list order.
Trip? liveTripOf(List<Trip> trips, DateTime now) {
  Trip? best;
  DateTime? bestStart;
  for (final t in trips) {
    if (tripDayOn(t.startDate, t.endDate, now) == null) continue;
    // tripDayOn != null guarantees startDate parses.
    final start = DateTime.parse(t.startDate!);
    if (bestStart == null || start.isAfter(bestStart)) {
      best = t;
      bestStart = start;
    }
  }
  return best;
}

/// The user's currently-live trip for the "Happening now" card
/// (specs/happening-now), derived from the owned-trips list. Owned trips only:
/// tripsProvider never includes shared-with-me trips. Recomputed whenever the
/// trips list is (re)loaded — like today-mode, "now" is sampled at build time,
/// so a trip going live at midnight shows up on the next list refresh, not
/// spontaneously.
final liveTripProvider = Provider<Trip?>((ref) {
  final trips = ref.watch(tripsProvider.select((s) => s.trips));
  return liveTripOf(trips, DateTime.now());
});
