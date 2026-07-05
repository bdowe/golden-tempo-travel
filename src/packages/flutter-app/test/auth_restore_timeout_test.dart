import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/auth_service.dart';
import 'package:travel_route_planner/services/auth_storage.dart';

/// AuthService whose `me` is scripted per test.
class _FakeAuthService extends AuthService {
  final Future<UserModel> Function() onMe;
  _FakeAuthService(this.onMe) : super(baseUrl: 'http://unused');

  @override
  Future<UserModel> me(String token) => onMe();
}

/// In-memory AuthStorage that records whether the token was cleared.
class _FakeAuthStorage extends AuthStorage {
  String? token;
  bool cleared = false;
  _FakeAuthStorage(this.token);

  @override
  Future<String?> loadToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async {
    token = null;
    cleared = true;
  }
}

void main() {
  late Duration originalTimeout;

  setUp(() {
    originalTimeout = AuthNotifier.restoreTimeout;
    AuthNotifier.restoreTimeout = const Duration(milliseconds: 50);
  });

  tearDown(() {
    AuthNotifier.restoreTimeout = originalTimeout;
  });

  test('restore timeout fails open signed-out and keeps the token', () async {
    final storage = _FakeAuthStorage('stored-token');
    // `me` never completes — simulates a hung/cold backend.
    final service = _FakeAuthService(() => Completer<UserModel>().future);
    final apiClient = ApiClient(baseUrl: 'http://unused');

    final notifier = AuthNotifier(service, storage, apiClient);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(notifier.state.initialized, isTrue);
    expect(notifier.state.isSignedIn, isFalse);
    expect(storage.cleared, isFalse, reason: 'timeout must keep the token');
    expect(storage.token, 'stored-token');
    expect(apiClient.authToken, isNull);
  });

  test('restore error clears the token', () async {
    final storage = _FakeAuthStorage('stored-token');
    final service =
        _FakeAuthService(() async =>
            throw const AuthException(statusCode: 401, message: 'invalid token'));
    final apiClient = ApiClient(baseUrl: 'http://unused');

    final notifier = AuthNotifier(service, storage, apiClient);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(notifier.state.initialized, isTrue);
    expect(notifier.state.isSignedIn, isFalse);
    expect(storage.cleared, isTrue);
    expect(storage.token, isNull);
  });

  test('restore success signs the user in', () async {
    final user = UserModel(
      id: 'u1',
      email: 'traveler@example.com',
      displayName: 'Traveler',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    final storage = _FakeAuthStorage('stored-token');
    final service = _FakeAuthService(() async => user);
    final apiClient = ApiClient(baseUrl: 'http://unused');

    final notifier = AuthNotifier(service, storage, apiClient);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(notifier.state.initialized, isTrue);
    expect(notifier.state.isSignedIn, isTrue);
    expect(apiClient.authToken, 'stored-token');
    expect(storage.cleared, isFalse);
  });
}
