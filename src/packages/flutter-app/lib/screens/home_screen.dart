import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../constants/app_info.dart';
import '../providers/auth_provider.dart';
import '../providers/recent_trip_provider.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/page_container.dart';
import 'route_optimizer_screen.dart';
import 'country_optimizer_screen.dart';
import 'agent_screen.dart';
import 'airbnb_parser_screen.dart';
import 'flight_search_screen.dart';
import 'trips_list_screen.dart';
import 'trip_detail_screen.dart';
import 'preferences_screen.dart';

/// Time-of-day greeting for the home header.
@visibleForTesting
String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  void _openAgent(BuildContext context, {String? initialMessage}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AgentScreen(initialMessage: initialMessage),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider).user;
    final recentTrip = ref.watch(recentTripProvider);

    return Scaffold(
      appBar: GradientAppBar(
        title: const Text(AppInfo.name),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle),
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(authProvider.notifier).logout();
              } else if (value == 'preferences') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PreferencesScreen()),
                );
              } else if (value == 'my_trips') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TripsListScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              if (user != null)
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(user.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              const PopupMenuItem<String>(
                value: 'my_trips',
                child: Row(
                  children: [
                    Icon(Icons.luggage, size: 20),
                    SizedBox(width: 8),
                    Text('My Trips'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'preferences',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 20),
                    SizedBox(width: 8),
                    Text('Travel profile'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20),
                    SizedBox(width: 8),
                    Text('Sign out'),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                _AgentHeroCard(onStart: _openAgent),

                const SizedBox(height: 28),

                // Divider label
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or plan it your way',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 20),

                // Most recently viewed trip — hidden until one has been opened.
                if (recentTrip != null) ...[
                  _RecentTripCard(
                    title: recentTrip.title,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            TripDetailScreen(tripId: recentTrip.tripId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Remaining manual tools, collapsed by default.
                Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade700.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.explore_outlined,
                          color: Colors.teal.shade700, size: 26),
                    ),
                    title: Text(
                      'Planning toolkit',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _ToolRow(
                          icon: MdiIcons.mapMarkerMultiple,
                          color: Colors.deepOrange.shade600,
                          title: 'Route Optimizer',
                          description:
                              'Map out the smartest path between your stops in a city',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const RouteOptimizerScreen()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _ToolRow(
                          icon: MdiIcons.airplane,
                          color: Colors.blue.shade700,
                          title: 'Find Flights',
                          description:
                              'Compare flights by price, schedule, and stops',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const FlightSearchScreen()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _ToolRow(
                          icon: MdiIcons.earth,
                          color: Colors.green.shade700,
                          title: 'Country Planner',
                          description:
                              'Order your countries around the best weather and seasons',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CountryOptimizerScreen()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _ToolRow(
                          icon: Icons.home_work_outlined,
                          color: Colors.pink.shade600,
                          title: 'Airbnb Lookup',
                          description:
                              'Paste an Airbnb link to preview photos, pricing, and details',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const AirbnbParserScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

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
  final void Function(BuildContext context, {String? initialMessage}) onStart;

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
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.shade900.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
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
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [
                      Colors.teal.shade900.withOpacity(0.88),
                      Colors.teal.shade900.withOpacity(0.35),
                    ],
                  ),
                ),
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
      constraints: const BoxConstraints(minHeight: 340),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.flight_takeoff, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            'Plan Your Trip with AI',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Just describe your dream trip and I\'ll find the places and build your itinerary.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withOpacity(0.85),
                ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => onStart(context),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.teal.shade800,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Start Planning',
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
                              color: Colors.teal.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      backgroundColor: Colors.white,
                      side: BorderSide.none,
                      onPressed: () => onStart(context, initialMessage: s),
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
  final VoidCallback onTap;

  const _RecentTripCard({required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade600, Colors.teal.shade900],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.shade900.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.luggage, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CONTINUE PLANNING',
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

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ToolRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
