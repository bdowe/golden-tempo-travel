import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_info.dart';
import '../navigation/app_nav.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../widgets/account_menu.dart';
import 'home_screen.dart';
import 'agent_screen.dart';
import 'trips_list_screen.dart';

/// Persistent navigation shell. The rail (wide) / bar (narrow) lives here,
/// outside the per-tab navigators, so it never moves when a page is pushed —
/// only the content area animates. Each tab keeps its own push stack, so a trip
/// opened in one tab stays put when you switch away and back.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navIndexProvider);
    final navKeys = ref.watch(tabNavKeysProvider);
    final isWide = MediaQuery.sizeOf(context).width >= kRailBreakpoint;

    void onSelect(int i) {
      if (i == ref.read(navIndexProvider)) {
        // Tapping the active tab again returns it to its root.
        navKeys[i].currentState?.popUntil((r) => r.isFirst);
      } else {
        ref.read(navIndexProvider.notifier).state = i;
      }
    }

    // The root navigator only holds the shell, so forward a system/browser back
    // to the active tab's navigator — otherwise nested pushes (trip detail, etc.)
    // couldn't be dismissed with the back button. At a tab root this is a no-op.
    final content = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        navKeys[ref.read(navIndexProvider)].currentState?.maybePop();
      },
      child: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < navKeys.length; i++)
            _TabNavigator(navKey: navKeys[i], child: _tabRoots[i]),
        ],
      ),
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: onSelect,
              labelType: NavigationRailLabelType.all,
              leading: const _RailBrand(),
              // Pin the account avatar to the bottom of the rail.
              trailingAtBottom: true,
              trailing: const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.lg),
                child: RailAccountButton(),
              ),
              destinations: [
                for (final d in navDestinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      body: content,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: [
          for (final d in navDestinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

const List<Widget> _tabRoots = [
  HomeScreen(),
  AgentScreen(),
  TripsListScreen(),
];

/// The Wayfare brand mark for the top of the rail — the persistent Site ID
/// (Krug). A compact icon badge + wordmark so it fits the narrow rail.
class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.flight_takeoff, color: AppColors.brand, size: 22),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            AppInfo.name,
            style: TextStyle(
              fontFamily: 'Playfair Display',
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tab's own [Navigator]: its root route is the tab screen; in-app pushes from
/// within the tab stack here so they animate inside the content area only.
class _TabNavigator extends StatelessWidget {
  final GlobalKey<NavigatorState> navKey;
  final Widget child;

  const _TabNavigator({required this.navKey, required this.child});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navKey,
      onGenerateRoute: (settings) => MaterialPageRoute(
        builder: (_) => child,
        settings: settings,
      ),
    );
  }
}
