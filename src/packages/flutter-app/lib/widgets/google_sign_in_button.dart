import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/api_client_provider.dart';
import '../providers/auth_provider.dart';

/// "Continue with Google" (specs/google-sso), including the OR divider above
/// it. Renders nothing while availability is unknown or when the backend has
/// no OAuth client configured, so the auth form is unchanged in that case.
///
/// Not a plugin flow: the whole tab navigates to the API's /auth/google
/// endpoint and comes back to /sso/<code> after the Google redirect dance,
/// so this must be a same-tab launch (NOT trackedLaunchUrl, which opens
/// externally and is for booking links).
class GoogleSignInButton extends ConsumerWidget {
  const GoogleSignInButton({super.key});

  void _start(WidgetRef ref) {
    final base = ref.read(apiClientProvider).baseUrl;
    // In Docker the base URL is the relative /api/v1; resolve it against the
    // page origin because launchUrl needs an absolute URL.
    final url = base.startsWith('http')
        ? '$base/auth/google'
        : Uri.base.resolve('$base/auth/google').toString();
    launchUrl(Uri.parse(url), webOnlyWindowName: '_self');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(googleSsoAvailableProvider);
    if (available.valueOrNull != true) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: theme.textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _start(ref),
          icon: Image.asset(
            'assets/images/google_g_logo.png',
            height: 20,
            width: 20,
          ),
          label: const Text('Continue with Google'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}
