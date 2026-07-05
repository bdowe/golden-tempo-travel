import 'dart:convert';
import '../models/user.dart';
import 'api_client.dart';

/// Account self-service endpoints (PATCH/DELETE /auth/account,
/// change-password, logout-all).
class AccountApiService {
  final ApiClient apiClient;

  AccountApiService(this.apiClient);

  Map<String, String> _headers() {
    final token = apiClient.authToken;
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  String _message(String body, int status) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return 'Request failed ($status)';
  }

  Future<UserModel> updateDisplayName(String displayName) async {
    final res = await apiClient.httpClient.patch(
      Uri.parse('${apiClient.baseUrl}/auth/account'),
      headers: _headers(),
      body: jsonEncode({'display_name': displayName}),
    );
    if (res.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(res.body));
    }
    throw Exception(_message(res.body, res.statusCode));
  }

  /// Returns the fresh session token minted after the change (every other
  /// session is revoked server-side).
  Future<({UserModel user, String token})> changePassword(
      String current, String newPassword) async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/auth/change-password'),
      headers: _headers(),
      body: jsonEncode({
        'current_password': current,
        'new_password': newPassword,
      }),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        user: UserModel.fromJson(body['user'] as Map<String, dynamic>),
        token: body['token'] as String,
      );
    }
    throw Exception(_message(res.body, res.statusCode));
  }

  Future<void> logoutAll() async {
    final res = await apiClient.httpClient.post(
      Uri.parse('${apiClient.baseUrl}/auth/logout-all'),
      headers: _headers(),
    );
    if (res.statusCode != 204) {
      throw Exception(_message(res.body, res.statusCode));
    }
  }

  Future<void> deleteAccount(String password) async {
    final res = await apiClient.httpClient.delete(
      Uri.parse('${apiClient.baseUrl}/auth/account'),
      headers: _headers(),
      body: jsonEncode({'password': password}),
    );
    if (res.statusCode != 204) {
      throw Exception(_message(res.body, res.statusCode));
    }
  }
}
