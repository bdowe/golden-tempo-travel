import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/local_guide.dart';
import '../models/local_recommendation.dart';
import '../providers/local_provider.dart';
import '../theme/app_colors.dart';
import '../theme/spacing.dart';
import '../widgets/empty_state.dart';
import '../widgets/gradient_app_bar.dart';
import '../widgets/local_rec_card.dart';

/// One narrative local guide: hero image, the local's byline, the story itself,
/// then the guide's pins in narrative order (as [LocalRecCard]s) and a small map
/// of every pin that has coordinates. Reached from the "Local intel" section of
/// a trip; [guide] is the list row, which carries the source attribution the
/// detail endpoint's guide object omits.
class LocalGuideDetailScreen extends ConsumerWidget {
  final LocalGuide guide;

  const LocalGuideDetailScreen({super.key, required this.guide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final detail = ref.watch(localGuideDetailProvider(guide.id));

    return Scaffold(
      appBar: GradientAppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text('Local guide', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => EmptyState(
          icon: Icons.menu_book,
          title: 'Could not load this guide',
          message: 'Check your connection and try again.',
          actions: [
            FilledButton.icon(
              onPressed: () => ref.invalidate(localGuideDetailProvider(guide.id)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
        data: (data) => _GuideBody(
          // The detail row is canonical for the narrative; the list row fills
          // in the attribution fields the detail join omits.
          guide: data.guide,
          fallback: guide,
          pins: data.recommendations,
          theme: theme,
        ),
      ),
    );
  }
}

class _GuideBody extends StatelessWidget {
  final LocalGuide guide;
  final LocalGuide fallback;
  final List<LocalRecommendation> pins;
  final ThemeData theme;

  const _GuideBody({
    required this.guide,
    required this.fallback,
    required this.pins,
    required this.theme,
  });

  String _pick(String primary, String secondary) =>
      primary.isNotEmpty ? primary : secondary;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.toolLocal;
    final title = _pick(guide.title, fallback.title);
    final body = _pick(guide.body, fallback.body);
    final heroUrl = _pick(guide.heroImageUrl, fallback.heroImageUrl);
    final sourceName = _pick(guide.sourceName, fallback.sourceName);
    final sourcePhotoUrl = _pick(guide.sourcePhotoUrl, fallback.sourcePhotoUrl);
    final placeLine = [
      _pick(guide.neighborhood, fallback.neighborhood),
      _pick(guide.city, fallback.city),
    ].where((s) => s.isNotEmpty).join(' · ');
    final mapped = pins
        .where((p) => p.latitude != null && p.longitude != null)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (heroUrl.isNotEmpty) ...[
          _HeroImage(url: heroUrl),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (placeLine.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            placeLine,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        // The local behind the guide — same face + name treatment as the
        // recommendation cards, so attribution reads consistently.
        if (sourceName.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: accent.withValues(alpha: 0.15),
                foregroundImage: sourcePhotoUrl.isNotEmpty
                    ? NetworkImage(sourcePhotoUrl)
                    : null,
                child: Text(
                  sourceName.characters.first.toUpperCase(),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'By $sourceName',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: accent, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.verified, size: 18, color: accent),
            ],
          ),
        ],
        if (body.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        ],
        if (pins.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Icon(Icons.place, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                'Places in this guide',
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${pins.length}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (mapped.isNotEmpty) ...[
            _GuideMap(pins: mapped),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final pin in pins) LocalRecCard(rec: pin),
        ] else ...[
          const SizedBox(height: AppSpacing.xl),
          EmptyState(
            icon: Icons.place,
            title: 'No places pinned yet',
            message: 'This guide is all narrative for now.',
            iconColor: accent.withValues(alpha: 0.5),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

/// The guide's hero photo, rounded like a card; falls back to a branded
/// placeholder block if the image fails to load.
class _HeroImage extends StatelessWidget {
  final String url;

  const _HeroImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.mdAll,
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => Container(
            decoration: BoxDecoration(gradient: AppColors.brandGradient),
            alignment: Alignment.center,
            child: const Icon(Icons.photo_outlined,
                size: 40, color: Colors.white70),
          ),
        ),
      ),
    );
  }
}

/// A small OSM map of the guide's mapped pins, numbered in narrative order.
/// TripMap is keyed to ItineraryItem (positions, categories, route line), so
/// this stays a purpose-built lightweight map with the same tile usage and the
/// same scroll-wheel opt-out (the map lives inside a ListView).
class _GuideMap extends StatefulWidget {
  final List<LocalRecommendation> pins;

  const _GuideMap({required this.pins});

  @override
  State<_GuideMap> createState() => _GuideMapState();
}

class _GuideMapState extends State<_GuideMap> {
  final MapController _controller = MapController();

  void _zoomBy(double delta) {
    try {
      _controller.move(
        _controller.camera.center,
        _controller.camera.zoom + delta,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final p in widget.pins) LatLng(p.latitude!, p.longitude!),
    ];

    const interaction = InteractionOptions(
      flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
    );
    final options = points.length == 1
        ? MapOptions(
            initialCenter: points.first,
            initialZoom: 13,
            interactionOptions: interaction,
          )
        : MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(32),
            ),
            interactionOptions: interaction,
          );

    return ClipRRect(
      borderRadius: AppRadius.mdAll,
      child: SizedBox(
        height: 240,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: options,
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.travelrouteplanner.app',
                ),
                MarkerLayer(
                  markers: [
                    for (var i = 0; i < points.length; i++)
                      Marker(
                        point: points[i],
                        width: 30,
                        height: 30,
                        child: _GuidePin(label: '${i + 1}'),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MapButton(icon: Icons.add, onTap: () => _zoomBy(1)),
                  const SizedBox(height: AppSpacing.sm),
                  _MapButton(icon: Icons.remove, onTap: () => _zoomBy(-1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered, local-accent map pin matching the trip map's pin look.
class _GuidePin extends StatelessWidget {
  final String label;

  const _GuidePin({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.toolLocal,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Small circular zoom control, matching the trip map's overlay buttons.
class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: scheme.onSurface),
        ),
      ),
    );
  }
}
