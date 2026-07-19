import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification.dart';
import '../services/notifications_api_service.dart';
import 'api_client_provider.dart';
import 'auth_provider.dart';

final notificationsApiServiceProvider =
    Provider<NotificationsApiService>((ref) {
  return NotificationsApiService(ref.watch(apiClientProvider));
});

/// The notification feed, newest-first (Wave 16). Refreshable via
/// `ref.invalidate` — the notification center re-reads it after mark-all-read.
final notificationsProvider =
    FutureProvider<List<AppNotification>>((ref) async {
  if (!ref.watch(authProvider).isSignedIn) return const [];
  return ref.watch(notificationsApiServiceProvider).list();
});

/// The unread badge count. Returns 0 when signed out; refetches when the
/// session changes. Refreshable via `ref.invalidate` after mark-all-read and
/// after opening the notification center.
final notificationsUnreadCountProvider = FutureProvider<int>((ref) async {
  if (!ref.watch(authProvider).isSignedIn) return 0;
  return ref.watch(notificationsApiServiceProvider).unreadCount();
});
