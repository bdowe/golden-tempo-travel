import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants/app_info.dart';
import 'providers/auth_provider.dart';
import 'theme/app_theme.dart';
import 'screens/landing_screen.dart';
import 'screens/app_shell.dart';

void main() {
  runApp(
    const ProviderScope(
      child: TravelRoutePlannerApp(),
    ),
  );
}

class TravelRoutePlannerApp extends StatelessWidget {
  const TravelRoutePlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AuthGate(),
    );
  }
}

/// Shows a loading splash until the stored session is checked, then routes to
/// the landing page (signed out) or the home screen (signed in).
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return auth.isSignedIn ? const AppShell() : const LandingScreen();
  }
}