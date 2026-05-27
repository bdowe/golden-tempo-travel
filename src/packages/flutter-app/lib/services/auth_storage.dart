import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the session token on-device so the user stays signed in across
/// app restarts. Backed by Keychain/Keystore on mobile and an encrypted
/// store on web.
class AuthStorage {
  static const _tokenKey = 'session_token';
  final FlutterSecureStorage _storage;

  AuthStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> loadToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);
}
