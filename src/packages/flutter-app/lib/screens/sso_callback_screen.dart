import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/l10n.dart';
import '../providers/auth_provider.dart';
import '../widgets/gradient_app_bar.dart';

/// Why the handoff didn't produce a session. Internal only — never shown or
/// sent anywhere; [SsoCallbackScreen.build] maps it to localized copy.
enum _SsoFailure { cancelled, expired }

/// Landing spot for the SSO redirect (Google or Apple), reachable at
/// /sso/<code> (specs/google-sso, specs/apple-sso). Swaps the one-time code
/// for a session on load and hands it to the auth provider; /sso/error means
/// the OAuth flow itself failed (declined consent, expired state, unverified
/// provider email).
class SsoCallbackScreen extends ConsumerStatefulWidget {
  final String code;
  const SsoCallbackScreen({super.key, required this.code});

  @override
  ConsumerState<SsoCallbackScreen> createState() => _SsoCallbackScreenState();
}

class _SsoCallbackScreenState extends ConsumerState<SsoCallbackScreen> {
  bool _loading = true;

  /// Which failure to explain, not the sentence itself: the copy is localized
  /// and resolved in [build] (specs/i18n-spanish). `_exchange` runs from
  /// `initState`, where an inherited-widget lookup isn't allowed.
  _SsoFailure? _failure;

  @override
  void initState() {
    super.initState();
    _exchange();
  }

  Future<void> _exchange() async {
    if (widget.code == 'error') {
      setState(() {
        _loading = false;
        _failure = _SsoFailure.cancelled;
      });
      return;
    }
    try {
      final res = await ref.read(authServiceProvider).exchangeSsoCode(widget.code);
      await ref.read(authProvider.notifier).adoptSession(res.token, res.user);
      if (mounted) {
        // AuthGate takes over: onboarding quiz for new users, app otherwise.
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failure = _SsoFailure.expired;
        });
      }
    }
  }

  void _backToSignIn() {
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
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.link_off, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              l10n.ssoFailedTitle,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              switch (_failure) {
                _SsoFailure.cancelled => l10n.ssoErrorCancelled,
                _SsoFailure.expired => l10n.ssoErrorExpired,
                null => '',
              },
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _backToSignIn,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(l10n.ssoBackToSignIn),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: GradientAppBar(title: Text(l10n.ssoTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );
  }
}
