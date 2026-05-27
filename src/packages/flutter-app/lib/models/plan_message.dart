enum MessageRole { user, assistant }

class PlanMessage {
  final MessageRole role;
  final String content;

  const PlanMessage({required this.role, required this.content});
}
