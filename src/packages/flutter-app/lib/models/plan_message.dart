enum MessageRole { user, assistant }

class PlanMessage {
  final MessageRole role;
  final String content;

  /// Compact UI stand-in. When set, the chat renders a system-style context
  /// chip with this label instead of a message bubble; [content] (e.g. the
  /// full refine seed) still goes to the server history untouched.
  final String? displayLabel;

  const PlanMessage({
    required this.role,
    required this.content,
    this.displayLabel,
  });
}
