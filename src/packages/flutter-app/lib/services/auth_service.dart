import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';

/// Wraps the /auth/* endpoints. Stateless — the session token is held by the
/// auth provider and passed in for authenticated calls.
class AuthService {
  final String baseUrl;
  final http.Client httpClient;

  AuthService({required this.baseUrl, http.Client? httpClient})
      : httpClient = httpClient ?? http.Client();

  Future<AuthResponse> register(
    String email,
    String password, {
    String? displayName,
  }) async {
    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'display_name': displayName,
      }),
    );
    if (res.statusCode == 201) {
      return AuthResponse.fromJson(jsonDecode(res.body));
    }
    throw _error(res);
  }

  Future<AuthResponse> login(String email, String password) async {
    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (res.statusCode == 200) {
      return AuthResponse.fromJson(jsonDecode(res.body));
    }
    throw _error(res);
  }

  Future<UserModel> me(String token) async {
    final res = await httpClient.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(res.body));
    }
    throw _error(res);
  }

  /// Marks the signup onboarding quiz as completed (or skipped).
  Future<UserModel> completeOnboarding(String token) async {
    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/onboarding-complete'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(res.body));
    }
    throw _error(res);
  }

  Future<void> logout(String token) async {
    await httpClient.post(
      Uri.parse('$baseUrl/auth/logout'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// Always resolves on 202 — the server never reveals whether the email
  /// has an account.
  Future<void> requestPasswordReset(String email) async {
    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/request-password-reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    if (res.statusCode != 202) throw _error(res);
  }

  /// Consumes the emailed reset code and sets the new password. All existing
  /// sessions are invalidated server-side.
  Future<void> resetPassword(String token, String newPassword) async {
    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );
    if (res.statusCode != 200) throw _error(res);
  }

  /// Extracts the server's error message, falling back to a generic one.
  AuthException _error(http.Response res) {
    String message = 'Request failed (${res.statusCode})';
    try {
      final body = jsonDecode(res.body);
      if (body is Map && body['message'] is String) {
        message = body['message'];
      }
    } catch (_) {}
    return AuthException(statusCode: res.statusCode, message: message);
  }
}

class AuthException implements Exception {
  final int statusCode;
  final String message;
  const AuthException({required this.statusCode, required this.message});

  @override
  String toString() => message;
}
