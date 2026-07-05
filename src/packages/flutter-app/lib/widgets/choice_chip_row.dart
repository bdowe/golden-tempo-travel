import 'package:flutter/material.dart';

/// A single-select row of [ChoiceChip]s. Tapping the selected chip again
/// clears the selection (passes null).
class ChoiceChipRow extends StatelessWidget {
  final List<String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const ChoiceChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: options.map((o) {
        return ChoiceChip(
          label: Text(o),
          selected: selected == o,
          onSelected: (sel) => onSelected(sel ? o : null),
        );
      }).toList(),
    );
  }
}
