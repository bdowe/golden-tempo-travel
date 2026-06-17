import 'package:flutter/material.dart';

/// Drop shadows for custom (non-Card) raised surfaces. Downward-offset so they
/// imply light from above, per the wiki's depth-and-shadows guidance — a flat,
/// evenly-blurred shadow looks artificial.
abstract final class AppShadows {
  /// Soft shadow for cards/containers rendered outside the Material `Card`
  /// (which gets its shadow from `cardTheme`).
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.10),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
}
