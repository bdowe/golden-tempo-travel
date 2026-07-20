import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../widgets/gradient_app_bar.dart';

/// Deep-link email verification, reachable at /verify/<token> straight from
/// the email. Consumes the token on load (POST /auth/verify-email) and shows
/// the outcome. The API's GET link endpoint remains for old emails.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final String token;
  const VerifyEmailScreen({super.key, required this.token});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _loading = true;

  /// Set when the token was rejected. Holds no message: the copy lives in the
  /// localizations and is picked in [build] (specs/i18n-spanish).
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    try {
      await ref.read(authServiceProvider).verifyEmail(widget.token);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _continue() {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final Widget body;
    if (_loading) {
      body = const CircularProgressIndicator();
    } else {
      final failed = _failed;
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              failed ? Icons.link_off : Icons.mark_email_read_outlined,
              size: 64,
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              failed ? l10n.verifyLinkExpiredTitle : l10n.verifySuccessTitle,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              failed
                  ? l10n.verifyLinkExpiredBody
                  : l10n.verifySuccessBody,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _continue,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(l10n.verifyContinue),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: GradientAppBar(title: Text(l10n.verifyTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );
  }
}
