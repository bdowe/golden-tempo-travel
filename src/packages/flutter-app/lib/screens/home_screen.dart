import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/recent_trip_provider.dart';
import '../widgets/gradient_app_bar.dart';
import 'route_optimizer_screen.dart';
import 'country_optimizer_screen.dart';
import 'agent_screen.dart';
import 'airbnb_parser_screen.dart';
import 'flight_search_screen.dart';
import 'trips_list_screen.dart';
import 'trip_detail_screen.dart';
import 'preferences_screen.dart';

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
        title: const Text('Travel Route Planner'),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),

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
                      'or use manual tools',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 16),

              // Most recently viewed trip — hidden until one has been opened.
              if (recentTrip != null) ...[
                _ToolRow(
                  icon: Icons.history,
                  color: Colors.teal.shade700,
                  title: 'Continue planning',
                  description: recentTrip.title,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripDetailScreen(tripId: recentTrip.tripId),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // My Trips
              _ToolRow(
                icon: Icons.luggage,
                color: Colors.teal.shade700,
                title: 'My Trips',
                description: 'View and manage trips saved from the AI agent',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TripsListScreen()),
                ),
              ),

              const SizedBox(height: 12),

              // Route Optimizer
              _ToolRow(
                icon: MdiIcons.mapMarkerMultiple,
                color: Colors.teal.shade700,
                title: 'Route Optimizer',
                description: 'Optimize routes for multiple locations in a city',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RouteOptimizerScreen()),
                ),
              ),

              const SizedBox(height: 12),

              // Find Flights
              _ToolRow(
                icon: MdiIcons.airplane,
                color: Colors.teal.shade700,
                title: 'Find Flights',
                description: 'Search and rank flights by price, time, and stops',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FlightSearchScreen()),
                ),
              ),

              const SizedBox(height: 12),

              // Country Planner
              _ToolRow(
                icon: MdiIcons.earth,
                color: Colors.teal.shade700,
                title: 'Country Planner',
                description: 'Plan multi-country trips with seasonal optimization',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CountryOptimizerScreen()),
                ),
              ),

              const SizedBox(height: 12),

              // Airbnb Parser
              _ToolRow(
                icon: Icons.home_work_outlined,
                color: Colors.teal.shade700,
                title: 'Airbnb Parser',
                description: 'Extract photos, pricing, and details from any Airbnb link',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AirbnbParserScreen()),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentHeroCard extends StatelessWidget {
  final void Function(BuildContext context, {String? initialMessage}) onStart;

  const _AgentHeroCard({required this.onStart});

  static const _suggestions = ['2 days in Paris', 'Museums in Rome', 'Weekend in Tokyo'];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 340),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.teal.shade600, Colors.teal.shade900],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.shade900.withOpacity( 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.smart_toy, size: 56, color: Colors.white),
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
              color: Colors.white.withOpacity( 0.85),
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
            children: _suggestions.map((s) => ActionChip(
              label: Text(s, style: TextStyle(color: Colors.teal.shade800, fontSize: 12, fontWeight: FontWeight.w500)),
              backgroundColor: Colors.white,
              side: BorderSide.none,
              onPressed: () => onStart(context, initialMessage: s),
            )).toList(),
          ),
        ],
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
      elevation: 2,
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
                  color: color.withOpacity( 0.1),
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
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
