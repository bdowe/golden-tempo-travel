import 'package:flutter/material.dart';

/// A section title with an optional trailing action (e.g. "Itinerary" + "Add
/// place"). Gives related groups a consistent header so the eye reads them as
/// sections rather than loose rows.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;

  const SectionHeader({super.key, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Wrap, not a Row: a wide action (e.g. two Add buttons) drops onto its
    // own line on narrow phones instead of overflowing. The SizedBox forces
    // full width so spaceBetween keeps the one-line case title-left,
    // action-right, exactly like the old Row.
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
