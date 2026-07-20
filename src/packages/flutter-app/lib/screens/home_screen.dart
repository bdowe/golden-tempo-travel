import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_info.dart';
import '../models/local_guide.dart';
import '../providers/auth_provider.dart';
import '../providers/live_trip_provider.dart';
import '../providers/local_provider.dart';
import '../providers/plan_provider.dart';
import '../providers/recent_trip_provider.dart';
import '../navigation/app_nav.dart';
import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';
import '../theme/spacing.dart';
import '../widgets/account_menu.dart';
import '../widgets/brand_logo.dart';
import '../widgets/continue_chats_section.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/live_trip_card.dart';
import '../widgets/page_container.dart';
import '../widgets/section_header.dart';
import 'guides_screen.dart';
import 'local_guide_detail_screen.dart';
import 'trip_detail_screen.dart';

/// Time-of-day greeting for the home header.
@visibleForTesting
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final recentTrip = ref.watch(recentTripProvider);
    // Populated app-wide: AppShell's IndexedStack keeps TripsListScreen
    // mounted, and its loadTrips() feeds tripsProvider — no fetch from here.
    final liveTrip = ref.watch(liveTripProvider);

    // The chat is a persistent tab, so "Let's go" / a suggestion switches to it
    // (and seeds the message) rather than pushing a one-off screen.
    void startPlanning({String? initialMessage}) {
      ref.read(navIndexProvider.notifier).state = AppTab.plan.index;
      if (initialMessage != null && initialMessage.isNotEmpty) {
        ref.read(planProvider.notifier).sendMessage(initialMessage);
      }
    }

    return Scaffold(
      appBar: GradientAppBar(
        centerTitle: false,
        // Brand mark on a light badge (so the black/gold logo reads on the teal
        // app bar) next to the wordmark in white.
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            BrandBadge(
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              child: BrandLogo.mark(size: 28),
            ),
            SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                AppInfo.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Playfair Display',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        actions: const [AccountMenu()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PageContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                _GreetingHeader(displayName: user?.displayName),

                const SizedBox(height: 16),

                // AI Travel Agent hero card
                _AgentHeroCard(onStart: startPlanning),

                const SizedBox(height: 28),

                // The trip happening today (specs/happening-now), then the
                // most recently viewed trip — the latter hidden when it *is*
                // the live trip, so the same trip never stacks twice.
                if (liveTrip != null) ...[
                  LiveTripCard(
                    trip: liveTrip,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TripDetailScreen(tripId: liveTrip.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // In-progress AI conversations that haven't produced a trip
                // yet (specs/continue-where-you-left-off) — same section as
                // My Trips, slotted below the live trip like there. Collapses
                // to nothing when empty, on error, or signed out.
                const ContinueChatsSection(),

                if (recentTrip != null &&
                    recentTrip.tripId != liveTrip?.id) ...[
                  _RecentTripCard(
                    title: recentTrip.title,
                    dateRange: recentTrip.dateRange,
                    status: recentTrip.status,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TripDetailScreen(tripId: recentTrip.tripId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Local guides discover row — published narrative guides
                // across all cities. Renders nothing while loading, on
                // error, or when there are none, so the section (header
                // included) only appears when there is something to show.
                const _LocalGuidesRow(),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String? displayName;

  const _GreetingHeader({required this.displayName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = displayName?.trim().split(RegExp(r'\s+')).first;
    final greeting = greetingForHour(DateTime.now().hour);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (firstName == null || firstName.isEmpty)
              ? greeting
              : '$greeting, $firstName',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Where are we off to next?',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AgentHeroCard extends StatelessWidget {
  final void Function({String? initialMessage}) onStart;

  const _AgentHeroCard({required this.onStart});

  static const _suggestions = [
    '2 days in Paris',
    'Museums in Rome',
    'Weekend in Tokyo'
  ];

  @override
  Widget build(BuildContext context) {
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
            // Scrim: darkest in the lower-left where the text and button sit,
            // lighter toward the upper-right so the photo shows through.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: AppColors.heroScrim),
              ),
            ),
            _heroContent(context),
          ],
        ),
      ),
    );
  }

  Widget _heroContent(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 440),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.flight_takeoff, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            'Plan less. Travel more.',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Describe the trip you\'re dreaming of and I\'ll build the full itinerary — places, days, and routes.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => onStart(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.brandDark,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.mdAll,
                ),
              ),
              child: const Text(
                'Let\'s go',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map((s) => ActionChip(
                      label: Text(s,
                          style: TextStyle(
                              color: AppColors.brandDark,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      backgroundColor: Colors.white,
                      side: BorderSide.none,
                      onPressed: () => onStart(initialMessage: s),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// One-tap way back into the most recently viewed trip, styled as a lighter
/// sibling of the hero card (same teal family as the app bar gradient).
class _RecentTripCard extends StatelessWidget {
  final String title;
  final String? dateRange;
  final String status;
  final VoidCallback onTap;

  const _RecentTripCard({
    required this.title,
    required this.dateRange,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Date + status snapshot, styled white-on-teal to match the card rather
    // than the light-surface StatusPill used elsewhere.
    final meta = <String>[
      if (dateRange != null && dateRange!.isNotEmpty) dateRange!,
      if (status.isNotEmpty)
        '${status[0].toUpperCase()}${status.substring(1)}'
      else
        'Draft',
    ].join('  ·  ');

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.mdAll,
        gradient: AppColors.brandGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.brandDark.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.luggage, color: Colors.white, size: 26),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PICK UP WHERE YOU LEFT OFF',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal discover row of published local guides across all cities.
/// Collapses to nothing (header included) while loading, on error, or when
/// no guides are published yet — the home screen just reads as before.
class _LocalGuidesRow extends ConsumerWidget {
  const _LocalGuidesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guides = ref.watch(allGuidesProvider).maybeWhen(
          data: (g) => g,
          orElse: () => const <LocalGuide>[],
        );
    if (guides.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Local guides',
          action: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GuidesScreen()),
            ),
            child: const Text('See all'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Room below the cards so their drop shadow isn't clipped by
            // the horizontal viewport.
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            itemCount: guides.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, i) => _GuideCard(guide: guides[i]),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// One tappable guide card in the discover row: hero image (branded fallback
/// when missing/broken), title, city, and the local's byline.
class _GuideCard extends StatelessWidget {
  final LocalGuide guide;

  const _GuideCard({required this.guide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = AppColors.toolLocal;

    return Container(
      width: 230,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.mdAll,
        boxShadow: AppShadows.soft,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => LocalGuideDetailScreen(guide: guide),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 88,
                width: double.infinity,
                child: guide.heroImageUrl.isNotEmpty
                    ? Image.network(
                        guide.heroImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _GuideImageFallback(),
                      )
                    : const _GuideImageFallback(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guide.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (guide.city.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          guide.city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (guide.sourceName.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.verified, size: 14, color: accent),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                'By ${guide.sourceName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Branded placeholder for a guide card whose hero image is missing or fails
/// to load — same treatment as the detail screen's hero fallback.
class _GuideImageFallback extends StatelessWidget {
  const _GuideImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: AppColors.brandGradient),
      alignment: Alignment.center,
      child: const Icon(Icons.menu_book, size: 28, color: Colors.white70),
    );
  }
}
