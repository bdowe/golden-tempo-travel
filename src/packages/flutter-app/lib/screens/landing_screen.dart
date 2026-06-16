import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../constants/app_info.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/page_container.dart';
import 'auth_screen.dart';

/// Marketing entry point shown to logged-out visitors. Brands the product and
/// showcases the core features, then funnels into the existing auth form:
/// "Get started" opens sign-up, "Sign in" opens login. On success the AuthGate
/// swaps this screen for the app automatically.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static void _openAuth(BuildContext context, {required bool isLogin}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AuthScreen(initialIsLogin: isLogin),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: GradientAppBar(
        centerTitle: false,
        title: const Text(
          AppInfo.name,
          style: TextStyle(
            fontFamily: 'Playfair Display',
            fontWeight: FontWeight.w600,
            fontSize: 24,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _openAuth(context, isLogin: true),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Sign in'),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: PageContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.sm),

                _LandingHero(
                  onGetStarted: () => _openAuth(context, isLogin: false),
                  onSignIn: () => _openAuth(context, isLogin: true),
                ),

                const SizedBox(height: AppSpacing.xl + AppSpacing.xs),

                Text(
                  'Everything you need to plan the trip',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                const _FeatureCard(
                  icon: Icons.auto_awesome,
                  title: 'AI Travel Agent',
                  description:
                      'Describe your dream trip and get a complete itinerary in seconds.',
                ),
                _FeatureCard(
                  icon: MdiIcons.mapMarkerMultiple,
                  color: AppColors.toolRoute,
                  title: 'Route Optimizer',
                  description:
                      'Map the smartest path between your stops in a city.',
                ),
                _FeatureCard(
                  icon: MdiIcons.earth,
                  color: AppColors.toolCountry,
                  title: 'Country Planner',
                  description:
                      'Order countries around the best weather and seasons.',
                ),
                _FeatureCard(
                  icon: MdiIcons.airplane,
                  color: AppColors.toolFlights,
                  title: 'Find Flights',
                  description:
                      'Compare flights by price, schedule, and stops.',
                ),

                const SizedBox(height: AppSpacing.xl),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => _openAuth(context, isLogin: false),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Get started',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Branded hero: full-bleed photo, teal scrim, tagline, and the primary CTAs.
/// Mirrors the home screen's `_AgentHeroCard` so the logged-out and logged-in
/// experiences read as one product.
class _LandingHero extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _LandingHero({required this.onGetStarted, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(
            color: AppColors.brandDark.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/hero_santorini.jpg',
                fit: BoxFit.cover,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroScrim),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 340),
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flight_takeoff,
                        size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Plan less. Travel more.',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your AI travel companion — describe the trip you want and '
                    'get a full day-by-day itinerary with routes, places, and '
                    'flights.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onGetStarted,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.teal.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Get started',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: onSignIn,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('I already have an account'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Informational feature row: colored icon chip + title + description. Mirrors
/// the home screen's `_ToolRow` minus the trailing chevron (these don't
/// navigate).
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? AppColors.brand;
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
