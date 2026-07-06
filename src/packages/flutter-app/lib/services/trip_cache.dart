import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip.dart';

/// A cached payload plus the moment it was saved, so the UI can say how
/// stale the copy is ("saved 2 hours ago").
typedef CachedTrips = ({List<Trip> trips, DateTime savedAt});
typedef CachedTrip = ({Trip trip, DateTime savedAt});

/// On-device, per-user cache of previously fetched trips so they stay
/// viewable (read-only) without a network. Backed by shared_preferences —
/// the same storage and user-scoped keying as `recent_trip_provider.dart` —
/// which is acceptable for v1 payload sizes (see specs/offline-trips).
///
/// Writes are best-effort: every write swallows storage errors so a cache
/// problem can never affect the online path. Reads treat any malformed entry
/// as a miss.
class TripCache {
  /// Signed-in user the cache belongs to; null when anonymous, in which case
  /// every operation no-ops (trips require sign-in anyway).
  final String? userId;

  TripCache(this.userId);

  /// Most-recently-viewed trip details kept per user; older ones are evicted.
  static const int maxCachedTrips = 10;

  static String _prefix(String userId) => 'trip_cache.$userId.';

  String get _listKey => '${_prefix(userId!)}list';
  String get _indexKey => '${_prefix(userId!)}index';
  String _tripKey(String tripId) => '${_prefix(userId!)}trip.$tripId';

  /// True when [e] is a network-level failure (no connection, timeout) as
  /// opposed to an HTTP error response. `package:http` >=1.0 wraps socket/IO
  /// failures in [http.ClientException] on every platform; the string check
  /// is belt-and-braces for raw dart:io SocketExceptions (dart:io itself is
  /// not importable on web). HTTP non-200s in TripsApiService are thrown as
  /// plain `Exception('... (status)')` and therefore never match — a
  /// 403/404/500 must NOT fall back to the cache.
  static bool isNetworkError(Object e) =>
      e is http.ClientException ||
      e is TimeoutException ||
      e.toString().contains('SocketException');

  /// Remembers the trips list. Fire-and-forget: never throws.
  Future<void> writeList(List<Trip> trips) async {
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _listKey,
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'trips': [for (final t in trips) t.toJson()],
        }),
      );
    } catch (_) {
      // Best-effort — a failed cache write must never surface.
    }
  }

  /// The last successfully fetched trips list, or null on miss/corruption.
  Future<CachedTrips?> readList() async {
    if (userId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_listKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.parse(m['saved_at'] as String);
      final trips = [
        for (final e in m['trips'] as List<dynamic>)
          Trip.fromJson(e as Map<String, dynamic>)
      ];
      return (trips: trips, savedAt: savedAt);
    } catch (_) {
      return null; // Malformed entry — treat as a miss.
    }
  }

  /// Remembers one trip's full detail and bumps it to the front of the MRU
  /// index, evicting beyond [maxCachedTrips]. Fire-and-forget: never throws.
  Future<void> writeTrip(Trip trip) async {
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _tripKey(trip.id),
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'trip': trip.toJson(),
        }),
      );
      final index = _readIndex(prefs)..remove(trip.id);
      index.insert(0, trip.id);
      for (final evicted in index.skip(maxCachedTrips)) {
        await prefs.remove(_tripKey(evicted));
      }
      await prefs.setStringList(
          _indexKey, index.take(maxCachedTrips).toList());
    } catch (_) {
      // Best-effort — a failed cache write must never surface.
    }
  }

  /// The last successfully fetched detail for [tripId], or null.
  Future<CachedTrip?> readTrip(String tripId) async {
    if (userId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tripKey(tripId));
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (
        trip: Trip.fromJson(m['trip'] as Map<String, dynamic>),
        savedAt: DateTime.parse(m['saved_at'] as String),
      );
    } catch (_) {
      return null; // Malformed entry — treat as a miss.
    }
  }

  /// Forgets a deleted trip so offline mode can't reopen it: drops its
  /// detail entry, its index slot, and its row in the cached list.
  Future<void> removeTrip(String tripId) async {
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tripKey(tripId));
      final index = _readIndex(prefs)..remove(tripId);
      await prefs.setStringList(_indexKey, index);
      final raw = prefs.getString(_listKey);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final trips = (m['trips'] as List<dynamic>)
            .where((e) => (e as Map<String, dynamic>)['id'] != tripId)
            .toList();
        await prefs.setString(
            _listKey, jsonEncode({'saved_at': m['saved_at'], 'trips': trips}));
      }
    } catch (_) {
      // Best-effort.
    }
  }

  List<String> _readIndex(SharedPreferences prefs) =>
      prefs.getStringList(_indexKey)?.toList() ?? <String>[];

  /// Removes every cached entry belonging to [userId]. Called on sign-out
  /// and account deletion (privacy: shared devices).
  static Future<void> clearForUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = _prefix(userId);
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(prefix)) await prefs.remove(key);
      }
    } catch (_) {
      // Best-effort.
    }
  }
}
