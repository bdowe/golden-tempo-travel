import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/local_guide.dart';
import '../providers/local_provider.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_container.dart';
import 'local_guide_detail_screen.dart';

/// All published local guides, grouped by city — the "See all" target of the
/// home discover row (guides-discover-row spec follow-up).
class GuidesScreen extends ConsumerWidget {
  const GuidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guides = ref.watch(allGuidesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Local guides')),
      body: PageContainer(
        child: guides.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => EmptyState(
            icon: Icons.cloud_off,
            title: 'Could not load guides',
            message: '$e',
            actions: [
              FilledButton(
                onPressed: () => ref.invalidate(allGuidesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (all) {
            if (all.isEmpty) {
              return const EmptyState(
                icon: Icons.menu_book_outlined,
                title: 'No guides yet',
                message:
                    'Guides from real locals appear here as they publish.',
              );
            }
            // Group by city, preserving the server's newest-first order
            // within and across groups.
            final byCity = <String, List<LocalGuide>>{};
            for (final g in all) {
              final city = g.city.isEmpty ? 'Elsewhere' : g.city;
              byCity.putIfAbsent(city, () => []).add(g);
            }
            final cities = byCity.keys.toList();

            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                for (final city in cities) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      city,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  for (final g in byCity[city]!) _GuideListTile(guide: g),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GuideListTile extends StatelessWidget {
  final LocalGuide guide;
  const _GuideListTile({required this.guide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.toolLocal.withValues(alpha: 0.15),
          foregroundImage: guide.sourcePhotoUrl.isNotEmpty
              ? NetworkImage(guide.sourcePhotoUrl)
              : null,
          child: Icon(Icons.menu_book_outlined,
              size: 18, color: AppColors.toolLocal),
        ),
        title: Text(guide.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: guide.sourceName.isEmpty
            ? null
            : Text('by ${guide.sourceName}'
                '${guide.neighborhood.isNotEmpty ? ' · ${guide.neighborhood}' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LocalGuideDetailScreen(guide: guide),
          ),
        ),
        titleTextStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
