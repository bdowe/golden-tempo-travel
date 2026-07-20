import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/api_client_provider.dart';
import '../providers/auth_provider.dart';
import '../services/account_api_service.dart';
import '../theme/spacing.dart';
import '../widgets/legal_links.dart';
import '../widgets/page_container.dart';
import '../widgets/section_header.dart';
import '../utils/snack.dart';

final accountApiServiceProvider = Provider<AccountApiService>((ref) {
  return AccountApiService(ref.watch(apiClientProvider));
});

/// Account self-service: display name, password change, sign-out-everywhere,
/// account deletion (user-accounts spec follow-ups).
class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  late final TextEditingController _nameController;
  final _currentPwController = TextEditingController();
  final _newPwController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: ref.read(authProvider).user?.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _currentPwController.dispose();
    _newPwController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (mounted) showSnack(context, msg);
  }

  String _errText(Object e) => '$e'.replaceFirst('Exception: ', '');

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _snack(_errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveName() => _run(() async {
        final name = _nameController.text.trim();
        final user =
            await ref.read(accountApiServiceProvider).updateDisplayName(name);
        ref.read(authProvider.notifier).setUser(user);
        _snack('Name updated');
      });

  Future<void> _changePassword() => _run(() async {
        final res = await ref.read(accountApiServiceProvider).changePassword(
              _currentPwController.text,
              _newPwController.text,
            );
        await ref.read(authProvider.notifier).adoptSession(res.token, res.user);
        _currentPwController.clear();
        _newPwController.clear();
        _snack('Password changed — other devices were signed out');
      });

  Future<void> _setReminders(bool enabled) => _run(() async {
        final user = await ref
            .read(accountApiServiceProvider)
            .updateEmailPreferences(remindersEnabled: enabled);
        ref.read(authProvider.notifier).setUser(user);
      });

  Future<void> _setNudges(bool enabled) => _run(() async {
        final user = await ref
            .read(accountApiServiceProvider)
            .updateEmailPreferences(nudgesEnabled: enabled);
        ref.read(authProvider.notifier).setUser(user);
      });

  Future<void> _logoutAll() => _run(() async {
        await ref.read(accountApiServiceProvider).logoutAll();
        // Our own session died too; sign out locally and let AuthGate route.
        await ref.read(authProvider.notifier).signOutLocally();
      });

  Future<void> _deleteAccount() async {
    final pwController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account, trips, preferences '
              'and alerts. There is no undo.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: pwController,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Confirm your password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      pwController.dispose();
      return;
    }
    await _run(() async {
      await ref
          .read(accountApiServiceProvider)
          .deleteAccount(pwController.text);
      await ref.read(authProvider.notifier).signOutLocally();
    });
    pwController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(title: const Text('Account settings')),
      body: PageContainer(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SectionHeader(title: 'Profile'),
            const SizedBox(height: AppSpacing.md),
            if (user != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Text(user.email, style: theme.textTheme.bodyMedium),
              ),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _saveName,
                child: const Text('Save name'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Password'),
            const SizedBox(height: AppSpacing.md),
            AutofillGroup(
              child: Column(
                children: [
                  TextField(
                    controller: _currentPwController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _newPwController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'New password (8+ characters)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _changePassword,
                child: const Text('Change password'),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Sessions'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Signs you out on every device, including this one.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Sign out everywhere'),
                onPressed: _busy ? null : _logoutAll,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Email preferences'),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Trip reminders'),
              subtitle: const Text(
                  'Nudges about upcoming trips and things left to book.'),
              value: user?.remindersEnabled ?? true,
              onChanged: _busy ? null : (v) => _setReminders(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Weekly planning ideas'),
              subtitle: const Text(
                  'A weekly email with destination ideas and inspiration.'),
              value: user?.nudgesEnabled ?? true,
              onChanged: _busy ? null : (v) => _setNudges(v),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Legal'),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: AppSpacing.sm,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Privacy Policy'),
                    onPressed: openPrivacyPolicy,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Terms of Service'),
                    onPressed: openTermsOfService,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(title: 'Danger zone'),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon:
                    Icon(Icons.delete_forever, color: theme.colorScheme.error),
                label: Text('Delete account',
                    style: TextStyle(color: theme.colorScheme.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.error),
                ),
                onPressed: _busy ? null : _deleteAccount,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
