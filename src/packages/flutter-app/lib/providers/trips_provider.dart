import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/trip.dart';
import '../services/trip_cache.dart';
import '../services/trips_api_service.dart';
import 'api_client_provider.dart';
import 'trip_cache_provider.dart';

final tripsApiServiceProvider = Provider<TripsApiService>((ref) {
  return TripsApiService(ref.watch(apiClientProvider));
});

class TripsState {
  final List<Trip> trips;
  final bool loading;
  final String? error;

  /// When non-null, [trips] is a cached copy served because the network was
  /// unreachable; the value is when that copy was saved. Null = live data.
  final DateTime? offlineSince;

  const TripsState(
      {this.trips = const [], this.loading = false, this.error, this.offlineSince});

  TripsState copyWith(
      {List<Trip>? trips,
      bool? loading,
      Object? error = _sentinel,
      Object? offlineSince = _sentinel}) {
    return TripsState(
      trips: trips ?? this.trips,
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
      offlineSince: offlineSince == _sentinel
          ? this.offlineSince
          : offlineSince as DateTime?,
    );
  }
}

const _sentinel = Object();

class TripsNotifier extends StateNotifier<TripsState> {
  final TripsApiService _service;
  final TripCache _cache;

  TripsNotifier(this._service, this._cache) : super(const TripsState());

  Future<void> loadTrips() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final trips = await _service.listTrips();
      state = state.copyWith(trips: trips, loading: false, offlineSince: null);
      // Write-through for offline viewing; fire-and-forget (never throws) so
      // the online path is unaffected.
      unawaited(_cache.writeList(trips));
    } catch (e) {
      // Only a network-level failure may fall back to the cached copy; an
      // HTTP error (401/403/500...) keeps the normal error path.
      if (TripCache.isNetworkError(e)) {
        final cached = await _cache.readList();
        if (cached != null) {
          state = state.copyWith(
            trips: cached.trips,
            loading: false,
            offlineSince: cached.savedAt,
          );
          return;
        }
      }
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> deleteTrip(String id) async {
    await _service.deleteTrip(id);
    state = state.copyWith(trips: state.trips.where((t) => t.id != id).toList());
    unawaited(_cache.removeTrip(id));
  }
}

final tripsProvider = StateNotifierProvider<TripsNotifier, TripsState>((ref) {
  return TripsNotifier(
      ref.watch(tripsApiServiceProvider), ref.watch(tripCacheProvider));
});
