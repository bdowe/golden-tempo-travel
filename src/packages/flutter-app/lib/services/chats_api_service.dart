import 'dart:convert';
import '../models/chat_session.dart';
import 'api_client.dart';

/// Wraps the authenticated /chats endpoints (resumable plan conversations).
/// Reads the bearer token from the shared ApiClient at call time so it always
/// reflects the current session.
class ChatsApiService {
  final ApiClient apiClient;

  ChatsApiService(this.apiClient);

  /// In-progress conversations, most recent first. Conversations that already
  /// produced a saved trip are excluded server-side.
  Future<List<ChatSessionSummary>> listResumableChats() async {
    final res = await apiClient.httpClient
        .get(Uri.parse('${apiClient.baseUrl}/chats'), headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((e) => ChatSessionSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to load conversations (${res.statusCode})');
  }

  /// Full transcript for resuming one conversation.
  Future<ChatSessionDetail> getChat(String chatId) async {
    final res = await apiClient.httpClient.get(
        Uri.parse('${apiClient.baseUrl}/chats/$chatId'),
        headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      return ChatSessionDetail.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to load conversation (${res.statusCode})');
  }

  Future<void> dismissChat(String chatId) async {
    final res = await apiClient.httpClient.delete(
        Uri.parse('${apiClient.baseUrl}/chats/$chatId'),
        headers: apiClient.jsonHeaders());
    if (res.statusCode != 204) {
      throw Exception('Failed to dismiss conversation (${res.statusCode})');
    }
  }
}
