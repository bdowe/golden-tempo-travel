import 'package:flutter/material.dart';
import '../models/booking_todo.dart';

/// A styled booking checklist card: an icon by kind, the title + dates, a
/// "Booked" checkbox, and a button that opens the pre-filled search link.
class BookingTodoCard extends StatelessWidget {
  final BookingTodo todo;
  final ValueChanged<bool> onBookedChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  const BookingTodoCard({
    super.key,
    required this.todo,
    required this.onBookedChanged,
    this.onOpen,
    this.onDelete,
  });

  IconData get _icon {
    switch (todo.kind) {
      case 'transport':
        return Icons.flight;
      case 'stay':
        return Icons.hotel;
      default:
        return Icons.check_circle_outline;
    }
  }

  String get _openLabel {
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
