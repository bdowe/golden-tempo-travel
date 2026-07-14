import 'package:flutter/material.dart';

/// Day-filter chips overlaid on a trip map: `All · Day 1 · … · Day N`
/// (specs/today-mode). [selected] is the 1-based day, null meaning All;
/// tapping a chip reports the new value through [onSelected] (tapping the
/// already-selected chip re-reports it — harmless for a filter).
///
/// Renders nothing when [dayCount] is 0 (undated trip with no day-tagged
/// items). Untagged items are an All-only affair, so there is deliberately
/// no "Unscheduled" chip.
///
/// The chips sit over satellite imagery, so they use the same translucent
/// dark scrim treatment as the map's segment labels and control buttons.
class MapDayChips extends StatelessWidget {
  final int dayCount;
  final int? selected;
  final ValueChanged<int?> onSelected;

  const MapDayChips({
    super.key,
    required this.dayCount,
    required this.selected,
    required this.onSelected,
  });

  Widget _chip({required String label, required int? value}) {
    final isSelected = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      // Compact: the row floats over the map and must not eat into it.
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      labelPadding: EdgeInsets.zero,
      showCheckmark: false,
      // Dark translucent scrim so the text reads over satellite imagery
      // (same treatment as TripMap's segment labels); selection is a solid
      // white ring + brighter fill rather than a theme tint, which would
      // vanish against imagery.
      backgroundColor: Colors.black.withValues(alpha: 0.6),
      selectedColor: Colors.black.withValues(alpha: 0.8),
      side: BorderSide(color: isSelected ? Colors.white : Colors.white24),
      labelStyle: TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (dayCount == 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(label: 'All', value: null),
          for (var d = 1; d <= dayCount; d++) ...[
            const SizedBox(width: 6),
            _chip(label: 'Day $d', value: d),
          ],
        ],
      ),
    );
  }
}
