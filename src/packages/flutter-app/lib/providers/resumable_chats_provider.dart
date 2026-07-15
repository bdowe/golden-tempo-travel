import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_session.dart';
import '../services/chats_api_service.dart';
import 'api_client_provider.dart';
import 'auth_provider.dart';

final chatsApiServiceProvider = Provider<ChatsApiService>((ref) {
  return ChatsApiService(ref.watch(apiClientProvider));
});

/// In-progress AI-planning conversations for the "Continue where you left off"
/// section (specs/continue-where-you-left-off). Empty when signed out; the UI
/// reads valueOrNull so a failed load (offline, degraded server) hides the
/// section instead of erroring the trips page. Rebuilds on sign-in/out;
/// refresh via ref.invalidate(resumableChatsProvider).
final resumableChatsProvider =
    FutureProvider<List<ChatSessionSummary>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return const <ChatSessionSummary>[];
  return ref.read(chatsApiServiceProvider).listResumableChats();
});
