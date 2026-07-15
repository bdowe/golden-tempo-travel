import 'package:json_annotation/json_annotation.dart';

part 'chat_session.g.dart';

/// One resumable AI-planning conversation ("continue where you left off").
/// Summary rows come from GET /chats; the full transcript from GET /chats/{id}.
@JsonSerializable()
class ChatSessionSummary {
  @JsonKey(name: 'chat_id')
  final String chatId;
  final String title;
  final String preview;
  @JsonKey(name: 'message_count')
  final int messageCount;
  @JsonKey(name: 'created_at')
  final String createdAt;
  @JsonKey(name: 'updated_at')
  final String updatedAt;

  const ChatSessionSummary({
    required this.chatId,
    required this.title,
    required this.preview,
    required this.messageCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatSessionSummary.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionSummaryFromJson(json);
  Map<String, dynamic> toJson() => _$ChatSessionSummaryToJson(this);
}

@JsonSerializable()
class ChatSessionMessage {
  final String role;
  final String content;

  const ChatSessionMessage({required this.role, required this.content});

  factory ChatSessionMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionMessageFromJson(json);
  Map<String, dynamic> toJson() => _$ChatSessionMessageToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ChatSessionDetail {
  @JsonKey(name: 'chat_id')
  final String chatId;
  final String title;

  /// Running compaction summary; empty when the conversation was never
  /// compacted. Restored as the resumed session's compactedSummary.
  final String summary;
  final List<ChatSessionMessage> messages;
  @JsonKey(name: 'updated_at')
  final String updatedAt;

  const ChatSessionDetail({
    required this.chatId,
    required this.title,
    required this.summary,
    required this.messages,
    required this.updatedAt,
  });

  factory ChatSessionDetail.fromJson(Map<String, dynamic> json) =>
      _$ChatSessionDetailFromJson(json);
  Map<String, dynamic> toJson() => _$ChatSessionDetailToJson(this);
}
