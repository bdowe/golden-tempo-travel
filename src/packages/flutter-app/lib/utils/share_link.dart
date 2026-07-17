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
