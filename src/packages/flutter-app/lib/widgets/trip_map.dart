import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/itinerary_item.dart';

/// Plots a trip's itinerary on an OpenStreetMap: a numbered, category-tinted pin
/// per place, a route line connecting them in itinerary order, auto-fit to the
/// trip's extent. Tapping a pin calls [onPinTap] with that item's index.
class TripMap extends StatelessWidget {
  final List<ItineraryItem> items;
  final int? selectedIndex;
  final void Function(int index)? onPinTap;

  const TripMap({
    super.key,
    required this.items,
    this.selectedIndex,
    this.onPinTap,
  });

  static bool _hasCoords(ItineraryItem i) =>
      i.latitude != 0 || i.longitude != 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Keep the original item index so taps map back to the itinerary list.
    final mapped = <({int index, ItineraryItem item, LatLng point})>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (_hasCoords(it)) {
        mapped.add((index: i, item: it, point: LatLng(it.latitude, it.longitude)));
      }
    }

    if (mapped.isEmpty) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          'No mapped places',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final points = mapped.map((m) => m.point).toList();

    // Single point: bounds collapse, so center with a sensible zoom.
    final MapOptions options = points.length == 1
        ? MapOptions(initialCenter: points.first, initialZoom: 13)
        : MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(points),
              padding: const EdgeInsets.all(32),
            ),
          );

    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.travelrouteplanner.app',
        ),
        if (points.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 3,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final m in mapped)
              Marker(
                point: m.point,
                width: 32,
                height: 32,
                child: _Pin(
                  label: '${m.item.position + 1}',
                  category: m.item.category,
                  selected: selectedIndex == m.index,
                  onTap: onPinTap == null ? null : () => onPinTap!(m.index),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Pin extends StatelessWidget {
  final String label;
  final String? category;
  final bool selected;
  final VoidCallback? onTap;

  const _Pin({
    required this.label,
    required this.category,
    required this.selected,
    this.onTap,
  });

  Color _color(ColorScheme scheme) {
    switch (category) {
      case 'restaurant':
        return Colors.deepOrange;
      case 'attraction':
        return scheme.primary;
      default:
        return scheme.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : color.withValues(alpha: 0.0),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.4 : 0.25),
              blurRadius: selected ? 6 : 3,
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
      ),
    );
  }
}
