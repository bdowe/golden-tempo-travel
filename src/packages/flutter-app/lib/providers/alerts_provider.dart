import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert_event.dart';
import '../models/price_alert.dart';
import '../services/alerts_api_service.dart';
import 'api_client_provider.dart';
import 'auth_provider.dart';

final alertsApiServiceProvider = Provider<AlertsApiService>((ref) {
  return AlertsApiService(ref.watch(apiClientProvider));
});

/// The notification feed, newest-first (specs/price-alerts-v2). Refreshable via
/// `ref.invalidate` — the notification center re-reads it after mark-all-read.
final alertEventsProvider = FutureProvider<List<AlertEvent>>((ref) async {
  if (!ref.watch(authProvider).isSignedIn) return const [];
  return ref.watch(alertsApiServiceProvider).listAlertEvents();
});

/// The unread badge count. Returns 0 when signed out; refetches when the
/// session changes. Refreshable via `ref.invalidate` after mark-all-read and
/// after opening the notification center.
final alertUnreadCountProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(authProvider).isSignedIn) return 0;
  return ref.watch(alertsApiServiceProvider).alertUnreadCount();
});

class AlertsState {
  final List<PriceAlert> alerts;
  final bool loading;
  final String? error;
  final bool loaded;

  const AlertsState({
    this.alerts = const [],
    this.loading = false,
    this.error,
    this.loaded = false,
  });

  AlertsState copyWith({
    List<PriceAlert>? alerts,
    bool? loading,
    Object? error = _sentinel,
    bool? loaded,
  }) {
    return AlertsState(
      alerts: alerts ?? this.alerts,
      loading: loading ?? this.loading,
      error: error == _sentinel ? this.error : error as String?,
      loaded: loaded ?? this.loaded,
    );
  }
}

const _sentinel = Object();

class AlertsNotifier extends StateNotifier<AlertsState> {
  final AlertsApiService _service;

  AlertsNotifier(this._service) : super(const AlertsState());

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final alerts = await _service.list();
      state = state.copyWith(alerts: alerts, loading: false, loaded: true);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e', loaded: true);
    }
  }

  /// Creates an alert; rethrows so callers can surface the message (cap,
  /// duplicate) inline.
  Future<PriceAlert> create(Map<String, dynamic> body) async {
    final alert = await _service.create(body);
    state = state.copyWith(alerts: [alert, ...state.alerts]);
    return alert;
  }

  Future<void> setPaused(String id, bool paused) async {
    final updated =
        await _service.patch(id, {'status': paused ? 'paused' : 'active'});
    state = state.copyWith(
      alerts: [
        for (final a in state.alerts) a.id == id ? updated : a,
      ],
    );
  }

  /// Sets the target price (the "notify at or below" threshold). The PATCH
  /// only accepts a positive value — the backend has no clear-to-any-drop path,
  /// so an alert with a target stays target-mode.
  Future<void> updateTarget(String id, double target) async {
    final updated = await _service.patch(id, {'target_price': target});
    state = state.copyWith(
      alerts: [
        for (final a in state.alerts) a.id == id ? updated : a,
      ],
    );
  }

  Future<void> remove(String id) async {
    await _service.delete(id);
    state = state.copyWith(
      alerts: [
        for (final a in state.alerts)
          if (a.id != id) a,
      ],
    );
  }
}

final alertsProvider =
    StateNotifierProvider<AlertsNotifier, AlertsState>((ref) {
  return AlertsNotifier(ref.watch(alertsApiServiceProvider));
});
