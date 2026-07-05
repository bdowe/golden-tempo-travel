import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/price_alert.dart';
import '../services/alerts_api_service.dart';
import 'api_client_provider.dart';

final alertsApiServiceProvider = Provider<AlertsApiService>((ref) {
  return AlertsApiService(ref.watch(apiClientProvider));
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
