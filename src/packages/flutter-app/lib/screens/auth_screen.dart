import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../widgets/brand_logo.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/legal_links.dart';
import '../utils/snack.dart';

class AuthScreen extends ConsumerStatefulWidget {
  /// Whether the form opens in sign-in (true) or create-account (false) mode.
  final bool initialIsLogin;

  const AuthScreen({super.key, this.initialIsLogin = true});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  late bool _isLogin = widget.initialIsLogin;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(authProvider.notifier);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final ok = _isLogin
        ? await notifier.login(email, password)
        : await notifier.register(email, password,
            displayName: _displayNameController.text.trim());
    // On success the AuthGate swaps the root from the landing page to the app.
    // When this screen was pushed on top of the landing page, pop it so the
    // app (now the root) is revealed instead of this form staying on top.
    if (ok && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _toggleMode() {
    setState(() => _isLogin = !_isLogin);
  }

  /// Two-step forgot-password flow: request a reset code by email, then
  /// enter the code + a new password. No URL routing needed, works on all
  /// platforms.
  Future<void> _forgotPassword() async {
    final requested = await showDialog<bool>(
      context: context,
      builder: (_) => _RequestResetDialog(
        initialEmail: _emailController.text.trim(),
        onRequest: (email) =>
            ref.read(authServiceProvider).requestPasswordReset(email),
      ),
    );
    if (requested != true || !mounted) return;
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _EnterResetCodeDialog(
        onReset: (code, password) =>
            ref.read(authServiceProvider).resetPassword(code, password),
      ),
    );
    if (done == true && mounted) {
      showSnack(context, 'Password updated — sign in with your new password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandLogo.mark(size: 72),
                  const SizedBox(height: 16),
                  Text(
                    _isLogin ? 'Welcome back' : 'Create your account',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Email is required';
                      if (!value.contains('@') || !value.contains('.')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) {
                      if ((v ?? '').isEmpty) return 'Password is required';
                      if (!_isLogin && v!.length < 8) {
                        return 'Password must be at least 8 characters';
                      }
                      return null;
                    },
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display name (optional)',
                      ),
                    ),
                  ],
                  if (auth.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      auth.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: auth.loading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: auth.loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isLogin ? 'Sign in' : 'Create account'),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 12),
                    const LegalAgreementText(),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: auth.loading ? null : _toggleMode,
                    child: Text(_isLogin
                        ? "Don't have an account? Sign up"
                        : 'Already have an account? Sign in'),
                  ),
                  if (_isLogin)
                    TextButton(
                      onPressed: auth.loading ? null : _forgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  const GoogleSignInButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Step 1 of forgot-password: request the emailed reset code.
class _RequestResetDialog extends StatefulWidget {
  final String initialEmail;
  final Future<void> Function(String email) onRequest;
  const _RequestResetDialog(
      {required this.initialEmail, required this.onRequest});

  @override
  State<_RequestResetDialog> createState() => _RequestResetDialogState();
}

class _RequestResetDialogState extends State<_RequestResetDialog> {
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail);
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onRequest(email);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset your password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
              'We\'ll email you a reset code if this address has an account.'),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(_sending ? 'Sending…' : 'Send code'),
        ),
      ],
    );
  }
}

/// Step 2 of forgot-password: enter the emailed code and a new password.
class _EnterResetCodeDialog extends StatefulWidget {
  final Future<void> Function(String code, String newPassword) onReset;
  const _EnterResetCodeDialog({required this.onReset});

  @override
  State<_EnterResetCodeDialog> createState() => _EnterResetCodeDialogState();
}

class _EnterResetCodeDialogState extends State<_EnterResetCodeDialog> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Paste the code from the email');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onReset(_code.text.trim(), _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your reset code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Check your inbox for the code we just sent.'),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Reset code'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'New password',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Set new password'),
        ),
      ],
    );
  }
}
