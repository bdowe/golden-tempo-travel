import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../models/accommodation.dart';
import '../models/itinerary_item.dart';
import '../theme/app_colors.dart';
import '../utils/trip_format.dart';
import 'app_map.dart';

/// Plots a trip's itinerary on a satellite basemap: a numbered, category-tinted
/// pin per place, a route line connecting them in itinerary order, auto-fit to
/// the trip's extent. Tapping a pin calls [onPinTap] with that item's position.
/// When [selectedPosition] changes the camera recenters on that place.
/// [accommodations] render as distinct stay markers (see [_StayPin]) that join
/// the auto-fit bounds but stay out of the route line and numbering.
class TripMap extends StatefulWidget {
  final List<ItineraryItem> items;
  final int? selectedPosition;
  final void Function(int position)? onPinTap;

  /// Stays to plot alongside the itinerary. Entries without coordinates are
  /// skipped; the default keeps existing call sites unchanged.
  final List<Accommodation> accommodations;

  /// Label text (e.g. "12 min") for the within-city leg leaving the item at the
  /// given position. Drawn at the midpoint of that segment. Empty => no labels.
  final Map<int, String> segmentLabels;

  /// When this value changes (by `==`), the camera re-fits to the current
  /// trip extent after the next frame. Lets callers that filter [items] /
  /// [accommodations] upstream (e.g. a day-chip selection) reframe the view
  /// without remounting the map by key, which would flash tiles. The default
  /// (never changing) keeps existing call sites unchanged.
  final Object? fitSignature;

  /// Message shown when nothing is mappable (no items or stays with
  /// coordinates). The default keeps existing call sites unchanged.
  final String emptyLabel;

  const TripMap({
    super.key,
    required this.items,
    this.selectedPosition,
    this.onPinTap,
    this.segmentLabels = const {},
    this.accommodations = const [],
    this.fitSignature,
    this.emptyLabel = 'No mapped places',
  });

  @override
  State<TripMap> createState() => _TripMapState();
}

class _TripMapState extends State<TripMap> {
  final MapController _controller = MapController();

  static bool _hasCoords(ItineraryItem i) =>
      i.latitude != 0 || i.longitude != 0;

  /// Clockwise angle (radians) from screen-up to the segment a->b as rendered
  /// on the Web Mercator map, so a rotated up-arrow lies along the polyline.
  static double _bearing(LatLng a, LatLng b) {
    double mercY(double lat) =>
        math.log(math.tan(math.pi / 4 + lat * math.pi / 360));
    // Both deltas must be in radians for the angle to come out right.
    final dLng =
        (((b.longitude - a.longitude + 540) % 360) - 180) * math.pi / 180;
    return math.atan2(dLng, mercY(b.latitude) - mercY(a.latitude));
  }

  /// The coordinate of the currently selected itinerary item, if mappable.
  LatLng? _selectedPoint() {
    final sel = widget.selectedPosition;
    if (sel == null) return null;
    for (final it in widget.items) {
      if (it.position == sel && _hasCoords(it)) {
        return LatLng(it.latitude, it.longitude);
      }
    }
    return null;
  }

  /// Frames the camera on the whole trip, mirroring the initial fit in [build] so
  /// the reset button returns to the opening view. Called from a button tap when
  /// the controller is already live, so it runs synchronously (a post-frame
  /// deferral would not fire without a frame being scheduled).
  void _fitToTrip(List<LatLng> points) {
    if (points.isEmpty) return;
    try {
      if (points.length == 1) {
        _controller.move(points.first, 13);
      } else {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(32),
          ),
        );
      }
    } catch (_) {}
  }

  void _zoomBy(double delta) {
    try {
      _controller.move(
        _controller.camera.center,
        _controller.camera.zoom + delta,
      );
    } catch (_) {}
  }

  /// Every coordinate the camera should frame: mapped items plus geocoded
  /// stays. Mirrors the fitPoints assembled in [build]. Static so it can run
  /// against an oldWidget's lists in [didUpdateWidget].
  static List<LatLng> _fitPointsOf(
    List<ItineraryItem> items,
    List<Accommodation> accommodations,
  ) {
    final points = <LatLng>[
      for (final it in items)
        if (_hasCoords(it)) LatLng(it.latitude, it.longitude),
    ];
    for (final a in accommodations) {
      final lat = a.latitude;
      final lng = a.longitude;
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        points.add(LatLng(lat, lng));
      }
    }
    return points;
  }

  List<LatLng> _fitPoints() => _fitPointsOf(widget.items, widget.accommodations);

  @override
  void didUpdateWidget(covariant TripMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signatureChanged = widget.fitSignature != oldWidget.fitSignature;
    // The set of mappable coordinates changed (a place added/removed/moved,
    // e.g. AI-streamed additions or a refresh delivering geocodes) while no
    // pin is selected: reframe so nothing sits off-screen. Order-insensitive
    // so a pure reorder never touches the camera. Skipped when the previous
    // frame had nothing mappable: build() then swaps the empty-state
    // Container for a freshly mounted FlutterMap whose initialCameraFit
    // already frames the new content.
    bool contentChanged() {
      if (widget.selectedPosition != null) return false;
      final oldPoints = _fitPointsOf(oldWidget.items, oldWidget.accommodations);
      if (oldPoints.isEmpty) return false;
      return !setEquals(_fitPoints().toSet(), oldPoints.toSet());
    }

    if (signatureChanged || contentChanged()) {
      // Re-fit after the frame that renders the new (filtered) content, so
      // the controller sees the updated layout. No-op when nothing is
      // mappable (the empty state has no live map to move).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitToTrip(_fitPoints());
      });
    }
    if (widget.selectedPosition != null &&
        widget.selectedPosition != oldWidget.selectedPosition) {
      final target = _selectedPoint();
      if (target == null) return;
      // Defer until after layout so the map controller is ready; zoom in enough
      // to break the place out of any marker cluster.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        var zoom = 15.0;
        try {
          zoom = _controller.camera.zoom < 15 ? 15 : _controller.camera.zoom;
        } catch (_) {}
        _controller.move(target, zoom);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final mapped = <({ItineraryItem item, LatLng point})>[];
    for (final it in widget.items) {
      if (_hasCoords(it)) {
        mapped.add((item: it, point: LatLng(it.latitude, it.longitude)));
      }
    }

    // Stays with real coordinates (null means "not geocoded"; 0,0 is junk).
    final stays = <({Accommodation stay, LatLng point})>[];
    for (final a in widget.accommodations) {
      final lat = a.latitude;
      final lng = a.longitude;
      if (lat != null && lng != null && (lat != 0 || lng != 0)) {
        stays.add((stay: a, point: LatLng(lat, lng)));
      }
    }

    if (mapped.isEmpty && stays.isEmpty) {
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          widget.emptyLabel,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final points = mapped.map((m) => m.point).toList();
    // Camera framing covers stays too; the route polyline sticks to [points].
    final fitPoints = [...points, for (final s in stays) s.point];
    final selected = _selectedPoint();

    // Travel-time labels at the midpoint of each within-city leg (only between
    // truly adjacent itinerary stops that are both mapped).
    final labelMarkers = <Marker>[];
    for (var k = 0; k < mapped.length - 1; k++) {
      final a = mapped[k];
      final b = mapped[k + 1];
      if (b.item.position != a.item.position + 1) continue;
      final label = widget.segmentLabels[a.item.position];
      if (label == null) continue;
      labelMarkers.add(
        Marker(
          point: LatLng(
            (a.point.latitude + b.point.latitude) / 2,
            (a.point.longitude + b.point.longitude) / 2,
          ),
          width: 84,
          height: 26,
          child: _SegmentLabel(text: label),
        ),
      );
    }

    // Direction arrows on every drawn segment (each consecutive pair of mapped
    // points, matching the polyline). Placed at the midpoint, or further along
    // when a travel-time label already occupies the midpoint.
    final arrowMarkers = <Marker>[];
    for (var k = 0; k < mapped.length - 1; k++) {
      final a = mapped[k];
      final b = mapped[k + 1];
      if (a.point == b.point) continue;
      final hasLabel = b.item.position == a.item.position + 1 &&
          widget.segmentLabels[a.item.position] != null;
      final t = hasLabel ? 0.7 : 0.5;
      arrowMarkers.add(
        Marker(
          point: LatLng(
            a.point.latitude + (b.point.latitude - a.point.latitude) * t,
            a.point.longitude + (b.point.longitude - a.point.longitude) * t,
          ),
          width: 18,
          height: 18,
          child: _SegmentArrow(angle: _bearing(a.point, b.point)),
        ),
      );
    }

    // Wheel scroll stays with the page (the map lives inside a ListView);
    // zooming is done via the on-map buttons or touch pinch.
    const interaction = InteractionOptions(
      flags: InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
    );

    // Center on the selected place when one is set (e.g. the map was just
    // (re)built after a list tap); otherwise fit the whole trip.
    final MapOptions options = selected != null
        ? MapOptions(
            initialCenter: selected,
            initialZoom: 15,
            interactionOptions: interaction,
            backgroundColor: appMapBackground,
          )
        : fitPoints.length == 1
            // Single point: bounds collapse, so center with a sensible zoom.
            ? MapOptions(
                initialCenter: fitPoints.first,
                initialZoom: 13,
                interactionOptions: interaction,
                backgroundColor: appMapBackground,
              )
            : MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(fitPoints),
                  padding: const EdgeInsets.all(32),
                ),
                interactionOptions: interaction,
                backgroundColor: appMapBackground,
              );

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: options,
          children: [
            ...appMapTileLayers(context),
            if (points.length >= 2)
              PolylineLayer(
                polylines: [
                  // Two passes make a thin line with a soft glow that stays
                  // legible over satellite imagery.
                  Polyline(
                    points: points,
                    strokeWidth: 6,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  Polyline(
                    points: points,
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ],
              ),
            if (arrowMarkers.isNotEmpty) MarkerLayer(markers: arrowMarkers),
            if (labelMarkers.isNotEmpty) MarkerLayer(markers: labelMarkers),
            // Stays live in their own layer, outside the clusterer: a trip has
            // few of them and "where am I sleeping" should never collapse into
            // an anonymous count bubble with sightseeing pins. Drawn beneath
            // the numbered pins so the primary interaction stays on top.
            if (stays.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (final s in stays)
                    Marker(
                      point: s.point,
                      width: 26,
                      height: 26,
                      child: _StayPin(
                        name: s.stay.name,
                        dates: tripDateRange(
                            s.stay.checkIn, s.stay.checkOut),
                      ),
                    ),
                ],
              ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                maxClusterRadius: 45,
                size: const Size(32, 32),
                padding: const EdgeInsets.all(40),
                markers: [
                  for (final m in mapped)
                    Marker(
                      point: m.point,
                      width: widget.selectedPosition == m.item.position
                          ? 28
                          : 24,
                      height: widget.selectedPosition == m.item.position
                          ? 28
                          : 24,
                      child: _Pin(
                        label: '${m.item.position + 1}',
                        category: m.item.category,
                        selected: widget.selectedPosition == m.item.position,
                        onTap: widget.onPinTap == null
                            ? null
                            : () => widget.onPinTap!(m.item.position),
                      ),
                    ),
                ],
                builder: (context, clusterMarkers) =>
                    _ClusterBubble(count: clusterMarkers.length),
              ),
            ),
            appMapAttribution(),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MapControlButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onTap: () => _zoomBy(1),
              ),
              const SizedBox(height: 8),
              MapControlButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onTap: () => _zoomBy(-1),
              ),
              const SizedBox(height: 8),
              MapControlButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Reset map',
                onTap: () => _fitToTrip(fitPoints),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An arrow on a route segment showing the direction of travel. [angle] is
/// clockwise radians from screen-up; the marker keeps the default
/// rotate-with-map behavior so the arrow stays aligned with the polyline.
class _SegmentArrow extends StatelessWidget {
  final double angle;
  const _SegmentArrow({required this.angle});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: const Icon(
        Icons.navigation,
        size: 14,
        color: Colors.white,
        shadows: [
          Shadow(color: Colors.black54, blurRadius: 3),
          Shadow(color: Colors.black54, blurRadius: 6),
        ],
      ),
    );
  }
}

/// A small pill showing a leg's travel time, centered on the route line.
class _SegmentLabel extends StatelessWidget {
  final String text;
  const _SegmentLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          // Dark translucent chip so the time reads cleanly over satellite
          // imagery and the route line beneath it.
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ClusterBubble extends StatelessWidget {
  final int count;
  const _ClusterBubble({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
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

  Color _color(ColorScheme scheme) => AppColors.forCategory(category, scheme);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _color(scheme);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // A permanent white ring keeps the small dots crisp over satellite
        // imagery; selection thickens the ring (and the marker itself grows).
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: selected ? 3 : 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.5 : 0.35),
              blurRadius: selected ? 6 : 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// A stay (accommodation) marker: a rounded square with a bed glyph in the
/// stays accent color, deliberately unlike the circular numbered itinerary
/// pins. Stays sit outside the position-based selection sync, so a tap shows
/// a self-contained tooltip (name + dates) instead of driving [TripMap.onPinTap].
class _StayPin extends StatelessWidget {
  final String name;

  /// Pre-formatted check-in – check-out range; null when dates are missing.
  final String? dates;

  const _StayPin({required this.name, this.dates});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: dates == null ? name : '$name\n$dates',
      triggerMode: TooltipTriggerMode.tap,
      child: Container(
        // Same white ring + shadow treatment as _Pin so it reads as part of
        // the family, but square where itinerary pins are round.
        decoration: BoxDecoration(
          color: AppColors.toolAirbnb,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.hotel, size: 14, color: Colors.white),
      ),
    );
  }
}
