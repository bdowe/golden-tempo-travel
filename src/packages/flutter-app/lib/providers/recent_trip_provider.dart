import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_provider.dart';

/// The trip detail screen the user last opened, remembered on-device so the
/// home screen can offer a one-tap way back into it.
class RecentTrip {
  final String tripId;
  final String title;

  const RecentTrip({required this.tripId, required this.title});
}

class RecentTripNotifier extends StateNotifier<RecentTrip?> {
  /// Signed-in user the stored value belongs to; null when anonymous, in which
  /// case nothing is recorded (trips require sign-in anyway).
  final String? _userId;

  RecentTripNotifier(this._userId) : super(null);

  String get _key => 'recent_trip.$_userId';

  /// Restore the last viewed trip for this user from device storage.
  Future<void> load() async {
    if (_userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = m['id'] as String?;
      final title = m['title'] as String?;
      if (id != null && id.isNotEmpty && title != null) {
        state = RecentTrip(tripId: id, title: title);
      }
    } catch (_) {
      // Malformed value — ignore and stay empty.
    }
  }

  /// Remember [tripId] as the most recently viewed trip. Call after a trip
  /// detail screen successfully loads.
  Future<void> record(String tripId, String title) async {
    if (_userId == null) return;
    state = RecentTrip(tripId: tripId, title: title);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({'id': tripId, 'title': title}));
  }

  /// Forget the recent trip if it points at [tripId] (used when a trip is
  /// deleted, so the home tile never targets a dead trip).
  Future<void> clearIfMatches(String tripId) async {
    if (_userId == null || state?.tripId != tripId) return;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Rebuilds on sign-in/out so each user only ever sees their own recent trip.
final recentTripProvider =
    StateNotifierProvider<RecentTripNotifier, RecentTrip?>((ref) {
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  return RecentTripNotifier(userId)..load();
});
