import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'snack.dart';

/// Base path the Flutter app is served under, injected by the deployment
/// build via --dart-define (like API_BASE_URL). Dart can't portably read the
/// base href.
const appBasePath =
    String.fromEnvironment('APP_BASE_PATH', defaultValue: '/');

/// Public URL for a share token: origin + basePath + share/<token>.
String shareUrl(String token) {
  String origin;
  try {
    origin = Uri.base.origin;
  } catch (_) {
    origin = ''; // non-http platform; a relative link still works in-app
  }
  return '$origin${appBasePath}share/$token';
}

/// Absolute URL for a trip's token-gated print view (owner-private export).
/// The API is same-origin behind the nginx gateway, so [apiBaseUrl] is the
/// app's configured API base ('/api/v1' in Docker/dev-gateway, an absolute
/// localhost URL under a bare `flutter run`). We resolve it to the current
/// origin the same way [shareUrl] does, so the link lands on the `/api/`
/// proxy in dev (:3000) and prod alike. NB: the API sits at `<origin>/api/v1`
/// even when the app itself is served under [appBasePath] (`/app/` in prod),
/// so this deliberately keys off the API base, not the app base path.
String exportPrintUrl(String apiBaseUrl, String token) =>
    _exportUrl(apiBaseUrl, token, 'print.html');

/// Absolute URL for a trip's token-gated calendar (.ics) export. See
/// [exportPrintUrl] for how the same-origin URL is built.
String exportIcsUrl(String apiBaseUrl, String token) =>
    _exportUrl(apiBaseUrl, token, 'calendar.ics');

/// Absolute URL for ONE trip event's token-gated .ics ([kind] is the server's
/// path segment: stay | segment | item). See [exportPrintUrl] for how the
/// same-origin URL is built.
String exportEventIcsUrl(
        String apiBaseUrl, String token, String kind, String id) =>
    _exportUrl(apiBaseUrl, token, 'event/$kind/$id.ics');

String _exportUrl(String apiBaseUrl, String token, String file) {
  final path = '$apiBaseUrl/export/$token/$file';
  // An absolute API base (bare `flutter run`) is already launch-ready.
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  // Relative base ('/api/v1', the Docker/gateway case): pin it to the origin
  // so url_launcher receives an absolute URL.
  String origin;
  try {
    origin = Uri.base.origin;
  } catch (_) {
    origin = '';
  }
  return '$origin$path';
}

/// Whether share actions present the OS share sheet (mobile) instead of a
/// clipboard copy (web/desktop, where navigator.share support is patchy and
/// the clipboard is the dependable UX). Drives menu labels too.
bool get shareUsesNativeSheet =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Shares [url] via the OS share sheet on mobile, or copies it to the
/// clipboard elsewhere (with [snackOnCopy] feedback). [sharePositionOrigin]
/// is the tapped control's global rect — REQUIRED on iPad, where the share
/// popover anchors to it and share_plus crashes without one.
Future<void> shareOrCopyLink(
  BuildContext context, {
  required String url,
  required String message,
  required String snackOnCopy,
  Rect? sharePositionOrigin,
}) async {
  if (shareUsesNativeSheet) {
    await SharePlus.instance.share(ShareParams(
      text: '$message\n$url',
      subject: message,
      sharePositionOrigin: sharePositionOrigin,
    ));
  } else {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showSnack(context, snackOnCopy);
  }
}
