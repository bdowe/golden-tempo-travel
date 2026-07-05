import 'package:flutter/material.dart';

/// A quiet one-line summary of a result set the agent found (flights, events,
/// local picks, ferries) — replaces inline card stacks in the chat. The full
/// results live on the trip detail screen; when [onTap] is set the chip shows
/// a "View in trip" affordance and links there.
class ResultSummaryChip extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final VoidCallback? onTap;

  const ResultSummaryChip({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      'View in trip',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 16, color: accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
