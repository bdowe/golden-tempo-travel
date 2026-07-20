import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../widgets/gradient_app_bar.dart';

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
  String? _error;

  @override
  void initState() {
    super.initState();
    _exchange();
  }

  Future<void> _exchange() async {
    if (widget.code == 'error') {
      setState(() {
        _loading = false;
        _error = 'Sign-in was cancelled or failed. Please try again.';
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
          _error = 'This sign-in link expired. Please try again.';
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
              'Sign-in didn\'t complete',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _backToSignIn,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Back to sign in'),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: const GradientAppBar(title: Text('Signing you in')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );
  }
}
