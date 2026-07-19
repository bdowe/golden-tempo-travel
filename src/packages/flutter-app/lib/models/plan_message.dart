import 'dart:convert';
import 'dart:typed_data';

enum MessageRole { user, assistant }

/// One image attached to a user chat message.
class PlanAttachment {
  /// Processed image bytes, ready for upload/thumbnail. Null for a
  /// resumed-transcript placeholder: the server strips pixels from persisted
  /// chats and keeps only [mediaType], so the bubble renders an "Image" chip
  /// and the attachment is excluded from resent history.
  final Uint8List? bytes;
  final String mediaType;

  PlanAttachment({required this.bytes, required this.mediaType});

  String? _base64;

  /// Base64 of [bytes], memoized — the whole history is re-serialized into
  /// every /plan request, so encoding per send would be O(turns) per image.
  String? get base64Data {
    final b = bytes;
    if (b == null) return null;
    return _base64 ??= base64Encode(b);
  }
}

class PlanMessage {
  final MessageRole role;
  final String content;

  /// Compact UI stand-in. When set, the chat renders a system-style context
  /// chip with this label instead of a message bubble; [content] (e.g. the
  /// full refine seed) still goes to the server history untouched.
  final String? displayLabel;

  /// Images attached to this (user) message.
  final List<PlanAttachment> attachments;

  const PlanMessage({
    required this.role,
    required this.content,
    this.displayLabel,
    this.attachments = const [],
  });
}
