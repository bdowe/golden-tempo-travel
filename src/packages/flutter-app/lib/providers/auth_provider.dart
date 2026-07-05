import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/auth_storage.dart';
import 'api_client_provider.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AuthService(baseUrl: apiClient.baseUrl, httpClient: apiClient.httpClient);
});

final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

class AuthState {
  final UserModel? user;
  final bool initialized; // false until the stored token has been checked
  final bool loading; // an auth request is in flight
  final String? error;

  const AuthState({
    this.user,
    this.initialized = false,
    this.loading = false,
    this.error,
  });

  bool get isSignedIn => user != null;

  AuthState copyWith({
    UserModel? user,
    bool? initialized,
    bool? loading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      initialized: initialized ?? this.initialized,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  /// How long the startup session restore may block the splash screen.
  @visibleForTesting
  static Duration restoreTimeout = const Duration(seconds: 8);

  final AuthService _service;
  final AuthStorage _storage;
  final ApiClient _apiClient;

  AuthNotifier(this._service, this._storage, this._apiClient)
      : super(const AuthState()) {
    _restore();
  }

  /// On startup, restore the session from a stored token if one exists.
  Future<void> _restore() async {
    final token = await _storage.loadToken();
    if (token == null) {
      state = state.copyWith(initialized: true);
      return;
    }
    try {
      final user = await _service.me(token).timeout(restoreTimeout);
      _apiClient.authToken = token;
      state = state.copyWith(user: user, initialized: true);
    } on TimeoutException {
      // Backend slow/unreachable — fail open as signed out, but KEEP the
      // stored token so the next launch retries the restore.
      _apiClient.authToken = null;
      state = state.copyWith(initialized: true, clearUser: true);
    } catch (_) {
      // Token invalid/expired — clear it and start signed out.
      await _storage.clearToken();
      _apiClient.authToken = null;
      state = state.copyWith(initialized: true, clearUser: true);
    }
  }

  Future<bool> login(String email, String password) =>
      _authenticate(() => _service.login(email, password));

  Future<bool> register(String email, String password, {String? displayName}) =>
      _authenticate(() => _service.register(email, password, displayName: displayName));

  Future<bool> _authenticate(Future<AuthResponse> Function() call) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await call();
      await _storage.saveToken(res.token);
      _apiClient.authToken = res.token;
      state = state.copyWith(user: res.user, loading: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      return false;
    } catch (e) {
      state = state.copyWith(loading: false, error: 'Something went wrong. Please try again.');
      return false;
    }
  }

  /// Marks onboarding done (quiz finished or skipped). On failure, unlocks
  /// locally anyway so the user is never trapped in the quiz — it simply
  /// reappears next session because the flag was never persisted.
  Future<void> completeOnboarding() async {
    try {
      final token = await _storage.loadToken();
      if (token != null) {
        final user = await _service.completeOnboarding(token);
        state = state.copyWith(user: user);
        return;
      }
    } catch (_) {/* fall through to local unlock */}
    final u = state.user;
    if (u != null) {
      state = state.copyWith(
        user: UserModel(
          id: u.id,
          email: u.email,
          displayName: u.displayName,
          isAdmin: u.isAdmin,
          needsOnboarding: false,
          createdAt: u.createdAt,
        ),
      );
    }
  }

  Future<void> logout() async {
    final token = await _storage.loadToken();
    if (token != null) {
      try {
        await _service.logout(token);
      } catch (_) {/* best effort */}
    }
    await _storage.clearToken();
    _apiClient.authToken = null;
    state = state.copyWith(clearUser: true, clearError: true);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(authServiceProvider),
    ref.watch(authStorageProvider),
    ref.watch(apiClientProvider),
  );
});
