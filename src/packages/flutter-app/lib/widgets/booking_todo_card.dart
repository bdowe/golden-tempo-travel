import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/booking_todo.dart';

IconData _kindIcon(BookingTodo todo) {
  switch (todo.kind) {
    case 'transport':
      switch (todo.provider) {
        case 'ferry':
          return Icons.directions_boat;
        case 'rome2rio': // ground leg on a driving/train/bus trip
          return Icons.directions;
        default:
          return Icons.flight;
      }
    case 'stay':
      return Icons.hotel;
    default:
      return Icons.check_circle_outline;
  }
}

/// Provider codes map to brand names, which are never translated — only the
/// surrounding "Open in ..." phrasing is (specs/i18n-spanish).
String? _providerBrand(String? provider) => switch (provider) {
      'airbnb' => 'Airbnb',
      'booking' => 'Booking.com',
      'google_flights' => 'Google Flights',
      'ferry' => 'Ferryhopper',
      'kayak' => 'Kayak',
      'rome2rio' => 'Rome2Rio',
      _ => null,
    };

String _providerOpenLabel(
    AppLocalizations l10n, BookingTodo todo, String? override) {
  if (override != null) return override;
  final brand = _providerBrand(todo.provider);
  return brand == null
      ? l10n.bookingCardOpenSearch
      : l10n.bookingCardOpenIn(brand);
}

/// A styled booking checklist card: an icon by kind, the title + dates, a
/// "Booked" checkbox, and a button that opens the pre-filled search link.
class BookingTodoCard extends StatelessWidget {
  final BookingTodo todo;
  final ValueChanged<bool> onBookedChanged;
  final VoidCallback? onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Overrides the open-button text (e.g. 'Find flights' when the action opens
  /// the in-app flight search instead of an external provider link).
  final String? openLabelOverride;

  /// Optional drag affordance (e.g. a ReorderableDragStartListener-wrapped
  /// drag_indicator) rendered at the end of the title row. The card stays
  /// index-agnostic — the list that owns the ordering builds the listener.
  final Widget? dragHandle;

  const BookingTodoCard({
    super.key,
    required this.todo,
    required this.onBookedChanged,
    this.onOpen,
    this.onEdit,
    this.onDelete,
    this.openLabelOverride,
    this.dragHandle,
  });

  IconData get _icon => _kindIcon(todo);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
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
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: l10n.bookingCardEdit,
                    onPressed: onEdit,
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.bookingCardRemove,
                    onPressed: onDelete,
                  ),
                if (dragHandle != null) dragHandle!,
              ],
            ),
            Row(
              children: [
                Checkbox(
                  value: todo.booked,
                  onChanged: (v) => onBookedChanged(v ?? false),
                ),
                Text(l10n.bookingCardBooked,
                    style: theme.textTheme.bodyMedium),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label:
                      Text(_providerOpenLabel(l10n, todo, openLabelOverride)),
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

  /// "Add details…": promotes this todo to a confirmed accommodation/segment
  /// via a prefilled add-sheet. Confirmed records are what viewers see and
  /// what calendar export / Tonight / map stay pins read, so this is the
  /// one-tap replacement for the retired Suggested-draft "Keep" flow. Null
  /// hides the menu (viewers, offline, custom todos).
  final VoidCallback? onAddDetails;

  const BookingTodoRow({
    super.key,
    required this.todo,
    required this.onBookedChanged,
    this.onOpen,
    this.openLabelOverride,
    this.onAddDetails,
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
            icon: const Icon(Icons.open_in_new, size: 18),
            // Booked rows recede: the link stays usable (re-check a price,
            // find the confirmation email's provider) but stops competing
            // with unbooked rows for attention.
            style: todo.booked
                ? TextButton.styleFrom(foregroundColor: muted)
                : null,
            label: Text(_providerOpenLabel(
                context.l10n, todo, openLabelOverride)),
          ),
          if (onAddDetails != null)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: muted),
              tooltip: context.l10n.bookingRowOptions,
              onSelected: (_) => onAddDetails!(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'details',
                  child: Text(context.l10n.bookingRowAddDetails),
                ),
              ],
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
