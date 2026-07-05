import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Space-dark canvas behind the tiles: unloaded/failed satellite tiles read as
/// "not lit yet" instead of a broken grey hole. Pass as
/// `MapOptions.backgroundColor` wherever [appMapTileLayers] is used.
const Color appMapBackground = Color(0xFF0A0F1A);

/// Shared basemap for every map in the app: Esri World Imagery satellite
/// tiles with a labels-only overlay designed for dark imagery, so maps get a
/// premium "satellite globe" look (à la Flighty) with readable place names.
///
/// Use [appMapTileLayers] as the first children of a [FlutterMap] and
/// [appMapAttribution] as the last child (attribution is required by both
/// Esri's and CARTO's tile usage terms).
List<Widget> appMapTileLayers(BuildContext context) {
  // panBuffer 0: two stacked layers double every tile request, and the default
  // 1-tile offscreen ring can exhaust the browser's request pool in bursts
  // (net::ERR_INSUFFICIENT_RESOURCES), leaving permanent grey holes. The evict
  // strategy re-fetches errored tiles when they scroll back into view instead
  // of keeping the hole.
  return [
    // Satellite base. Note the ArcGIS {z}/{y}/{x} path order.
    TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.travelrouteplanner.app',
      panBuffer: 0,
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    ),
    // Place/street names with a light halo, made to sit over dark basemaps.
    TileLayer(
      urlTemplate:
          'https://basemaps.cartocdn.com/rastertiles/dark_only_labels/{z}/{x}/{y}{r}.png',
      userAgentPackageName: 'com.travelrouteplanner.app',
      retinaMode: RetinaMode.isHighDensity(context),
      panBuffer: 0,
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
    ),
  ];
}

/// Collapsed-to-an-icon attribution for the layers in [appMapTileLayers].
Widget appMapAttribution() {
  return RichAttributionWidget(
    alignment: AttributionAlignment.bottomLeft,
    showFlutterMapAttribution: false,
    openButton: (context, open) => IconButton(
      onPressed: open,
      tooltip: 'Map credits',
      icon: const Icon(Icons.info_outline, size: 16, color: Colors.white70),
    ),
    attributions: const [
      TextSourceAttribution(
        'Powered by Esri — Source: Esri, Maxar, Earthstar Geographics',
        prependCopyright: false,
      ),
      TextSourceAttribution('CARTO'),
      TextSourceAttribution('OpenStreetMap contributors'),
    ],
  );
}

/// A small circular control overlaid on the map (zoom in/out, reset). Dark
/// and translucent so it reads as a frosted chip over satellite imagery.
class MapControlButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback onTap;

  const MapControlButton({
    super.key,
    required this.icon,
    this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.black.withValues(alpha: 0.55),
      shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
