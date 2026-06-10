import 'package:flutter/material.dart';
import '../models/booking_todo.dart';

IconData _kindIcon(BookingTodo todo) {
  switch (todo.kind) {
    case 'transport':
      return Icons.flight;
    case 'stay':
      return Icons.hotel;
    default:
      return Icons.check_circle_outline;
  }
}

String _providerOpenLabel(BookingTodo todo, String? override) {
  if (override != null) return override;
  switch (todo.provider) {
    case 'airbnb':
      return 'Open in Airbnb';
    case 'booking':
      return 'Open in Booking.com';
    case 'google_flights':
      return 'Open in Google Flights';
    case 'kayak':
      return 'Open in Kayak';
    case 'rome2rio':
      return 'Open in Rome2Rio';
    default:
      return 'Open search';
  }
}

/// A styled booking checklist card: an icon by kind, the title + dates, a
/// "Booked" checkbox, and a button that opens the pre-filled search link.
class BookingTodoCard extends StatelessWidget {
  final BookingTodo todo;
  final ValueChanged<bool> onBookedChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  /// Overrides the open-button text (e.g. 'Find flights' when the action opens
  /// the in-app flight search instead of an external provider link).
  final String? openLabelOverride;

  const BookingTodoCard({
    super.key,
    required this.todo,
    required this.onBookedChanged,
    this.onOpen,
    this.onDelete,
    this.openLabelOverride,
  });

  IconData get _icon => _kindIcon(todo);

  String get _openLabel => _providerOpenLabel(todo, openLabelOverride);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(todo.title, style: theme.textTheme.titleSmall),
                      if (todo.subtitle != null && todo.subtitle!.isNotEmpty)
                        Text(
                          todo.subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove',
                    onPressed: onDelete,
                  ),
              ],
            ),
            Row(
              children: [
                Checkbox(
                  value: todo.booked,
                  onChanged: (v) => onBookedChanged(v ?? false),
                ),
                Text('Booked', style: theme.textTheme.bodyMedium),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(_openLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim one-line booking row for embedding inside the itinerary's city
/// groups: kind icon, title + dates, a compact "Booked" checkbox, and the
/// open-search action. Auto bookings only — no delete affordance.
class BookingTodoRow extends StatelessWidget {
  final BookingTodo todo;
  final ValueChanged<bool> onBookedChanged;
  final VoidCallback? onOpen;

  /// Same override as [BookingTodoCard.openLabelOverride].
  final String? openLabelOverride;

  const BookingTodoRow({
    super.key,
    required this.todo,
    required this.onBookedChanged,
    this.onOpen,
    this.openLabelOverride,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
      child: Row(
        children: [
          Icon(_kindIcon(todo), size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todo.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: todo.booked ? muted : null,
                    decoration: todo.booked ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (todo.subtitle != null && todo.subtitle!.isNotEmpty)
                  Text(
                    todo.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(_providerOpenLabel(todo, openLabelOverride)),
          ),
          // Last so the fixed-width checkboxes stay flush right and aligned
          // across rows despite varying button-label widths.
          Checkbox(
            value: todo.booked,
            onChanged: (v) => onBookedChanged(v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
