import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Same-origin legal pages served by the nginx gateway at the site root
/// (`/privacy`, `/terms`) — outside the Flutter app's own base path, so they
/// are opened as absolute URLs off the current origin rather than routed
/// in-app (the same origin-derivation trick trip sharing uses).
Future<void> openLegalPage(String path) async {
  String origin;
  try {
    origin = Uri.base.origin; // http(s) platforms
  } catch (_) {
    // Non-web platform: fall back to the gateway default (PUBLIC_BASE_URL's
    // documented default), where the pages are served in dev and deploy.
    origin = 'http://localhost:3000';
  }
  final uri = Uri.tryParse('$origin$path');
  if (uri != null) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> openPrivacyPolicy() => openLegalPage('/privacy');
Future<void> openTermsOfService() => openLegalPage('/terms');

/// "By signing up you agree to the Terms of Service and Privacy Policy" —
/// small print with tappable links, shown under the sign-up form.
class LegalAgreementText extends StatelessWidget {
  const LegalAgreementText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('By signing up you agree to the ', style: base),
        _InlineLink(
            label: 'Terms of Service',
            style: base,
            onTap: openTermsOfService),
        Text(' and ', style: base),
        _InlineLink(
            label: 'Privacy Policy', style: base, onTap: openPrivacyPolicy),
        Text('.', style: base),
      ],
    );
  }
}

class _InlineLink extends StatelessWidget {
  final String label;
  final TextStyle? style;
  final Future<void> Function() onTap;

  const _InlineLink(
      {required this.label, required this.style, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: (style ?? const TextStyle()).copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
