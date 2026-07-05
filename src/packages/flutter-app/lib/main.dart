import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'constants/app_info.dart';
import 'providers/auth_provider.dart';
import 'theme/app_theme.dart';
import 'screens/landing_screen.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding_quiz_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/shared_trip_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/splash_screen.dart';

void main() {
  // Path-style URLs on web (https://host/app/share/x instead of /#/share/x).
  // The engine strips the base href before routing, so onGenerateRoute sees
  // clean paths in both dev (/) and deployment (/app/). No-op off web.
  usePathUrlStrategy();
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
      // Route by URL so share links work signed-out. Everything else lands
      // on AuthGate, preserving the existing splash -> landing/quiz/shell
      // flow. Legacy /#/share links are rewritten by the index.html shim.
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '/');
        final segments = uri?.pathSegments ?? const <String>[];
        if (segments.length == 2 && segments[0] == 'share') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => SharedTripScreen(token: segments[1]),
          );
        }
        if (segments.length == 2 && segments[0] == 'reset') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => ResetPasswordScreen(token: segments[1]),
          );
        }
        if (segments.length == 2 && segments[0] == 'verify') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => VerifyEmailScreen(token: segments[1]),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AuthGate(),
        );
      },
    );
  }
}

/// Shows a loading splash until the stored session is checked, then routes to
/// the landing page (signed out), the one-time signup quiz (signed in but not
/// yet onboarded), or the home screen.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final Widget child;
    if (!auth.initialized) {
      child = const SplashScreen();
    } else if (!auth.isSignedIn) {
      child = const LandingScreen();
    } else {
      child = auth.user!.needsOnboarding
          ? const OnboardingQuizScreen()
          : const AppShell();
    }
    // Fade between splash and destination so instant auth resolution isn't a
    // one-frame hard cut. Branches are distinct types, so no keys needed.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: child,
    );
  }
}