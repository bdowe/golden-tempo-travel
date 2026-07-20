import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/api_client_provider.dart';
import '../providers/auth_provider.dart';

/// "Continue with Apple" (specs/apple-sso). Same server-side redirect flow as
/// the Google button — the whole tab navigates to /auth/apple and comes back
/// to /sso/<code> — styled per Apple's HIG (black fill, white logo + text).
/// Renders nothing when the backend has no Apple credentials configured.
class AppleSignInButton extends ConsumerWidget {
  const AppleSignInButton({super.key});

  void _start(WidgetRef ref) {
    final base = ref.read(apiClientProvider).baseUrl;
    // In Docker the base URL is the relative /api/v1; resolve it against the
    // page origin because launchUrl needs an absolute URL.
    final url = base.startsWith('http')
        ? '$base/auth/apple'
        : Uri.base.resolve('$base/auth/apple').toString();
    launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(appleSsoAvailableProvider);
    if (available.valueOrNull != true) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: () => _start(ref),
      // Material Icons ships an Apple glyph — no bundled asset needed
      // (unlike the Google "G", which has no font equivalent).
      icon: const Icon(Icons.apple, size: 22),
      label: const Text('Continue with Apple'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}
