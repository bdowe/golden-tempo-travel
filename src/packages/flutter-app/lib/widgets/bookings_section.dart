import 'package:flutter/material.dart';
import '../models/accommodation.dart';
import '../models/trip.dart';
import '../models/trip_segment.dart';
import '../theme/spacing.dart';
import '../utils/tracked_launch.dart';
import 'status_pill.dart';

/// "Your bookings" hub in trip detail: the stays and transport segments the
/// user has actually saved (distinct from the auto-derived booking checklist),
/// plus itinerary-seeded Suggested drafts (auto=true) the user can keep, edit,
/// or dismiss. Callbacks land in the screen, which persists via the
/// accommodations/segments endpoints and reloads the trip.
class BookingsSection extends StatelessWidget {
  final Trip trip;

  /// Sync-owned lists (drafts + confirmed) held by the screen — the booking
  /// drafts sync replaces them after each load, so they're passed in rather
  /// than read from the immutable [trip].
  final List<Accommodation> stays;
  final List<TripSegment> segments;
  final VoidCallback onAddStay;
  final void Function(Accommodation) onDeleteStay;
  final void Function(Accommodation) onEditStay;
  final void Function(Accommodation) onConfirmStay;
  final VoidCallback onAddSegment;
  final void Function(TripSegment) onDeleteSegment;
  final void Function(TripSegment) onEditSegment;
  final void Function(TripSegment) onConfirmSegment;

  /// "Booked" checkbox toggles on confirmed rows (drafts keep their
  /// keep/edit/dismiss actions instead — checking a suggestion would silently
  /// confirm it). Null disables the checkboxes (offline), like the reorder
  /// callbacks; in read-only mode they render disabled but still show state.
  final void Function(Accommodation, bool)? onStayBookedChanged;
  final void Function(TripSegment, bool)? onSegmentBookedChanged;

  /// Drag-reorder callbacks, `ReorderableListView.onReorder`-shaped. Null
  /// disables reordering for that group (viewer follows, offline). Indexes
  /// refer to [stays]/[segments] directly — when reordering is enabled the
  /// widget is not read-only, so the visible list IS the passed-in list.
  final void Function(int oldIndex, int newIndex)? onReorderStays;
  final void Function(int oldIndex, int newIndex)? onReorderSegments;

  /// Read-only mode (viewer follows): stays and transport render without the
  /// add buttons and edit/delete icons, and Suggested drafts are hidden
  /// entirely (the server already withholds them from viewers).
  final bool readOnly;

  const BookingsSection({
    super.key,
    required this.trip,
    required this.stays,
    required this.segments,
    required this.onAddStay,
    required this.onDeleteStay,
    required this.onEditStay,
    required this.onConfirmStay,
    required this.onAddSegment,
    required this.onDeleteSegment,
    required this.onEditSegment,
    required this.onConfirmSegment,
    this.onStayBookedChanged,
    this.onSegmentBookedChanged,
    this.onReorderStays,
    this.onReorderSegments,
    this.readOnly = false,
  });

  static IconData _modeIcon(String mode) => switch (mode) {
        'flight' => Icons.flight_takeoff,
        'train' => Icons.train_outlined,
        'bus' => Icons.directions_bus_outlined,
        'car' => Icons.directions_car_outlined,
        'ferry' => Icons.directions_boat_outlined,
        _ => Icons.route_outlined,
      };

  /// Opens a saved booking's own link — still a booking handoff, so it counts
  /// toward the attach rate under the provider the user recorded (if any).
  Future<void> _open(BuildContext context, String url,
      {String? provider, required String kind}) async {
    await trackedLaunchUrl(
      context,
      url,
      provider: (provider == null || provider.isEmpty)
          ? 'unknown'
          : provider.toLowerCase(),
      surface: 'bookings_hub',
      tripId: trip.id,
      kind: kind,
    );
  }

  Widget _suggestedPill(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(left: AppSpacing.sm),
        child: StatusPill.custom(
          label: 'Suggested',
          background: theme.colorScheme.secondaryContainer,
          foreground: theme.colorScheme.onSecondaryContainer,
        ),
      );

  /// Trailing actions for a Suggested draft: keep (confirm as-is), edit
  /// (prefilled sheet), dismiss (tombstoned server-side so it won't re-seed).
  Widget _draftActions(
      {required VoidCallback onKeep,
      required VoidCallback onEdit,
      required VoidCallback onDismiss,
      Widget? dragHandle}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.check, size: 18),
          tooltip: 'Keep',
          onPressed: onKeep,
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 18),
          tooltip: 'Edit',
          onPressed: onEdit,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: 'Dismiss suggestion',
          onPressed: onDismiss,
        ),
        if (dragHandle != null) dragHandle,
      ],
    );
  }

  /// Compact "Booked" checkbox for confirmed rows, shrunk to sit in the
  /// trailing icon row (same treatment as BookingTodoRow's). A null
  /// [onChanged] renders it disabled but still showing state.
  Widget _bookedCheckbox(
          {required bool value, required void Function(bool)? onChanged}) =>
      Checkbox(
        value: value,
        onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  /// Muted + struck-through once booked, mirroring the checklist rows.
  TextStyle? _bookedTitleStyle(ThemeData theme, bool booked) => booked
      ? TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          decoration: TextDecoration.lineThrough,
        )
      : null;

  Widget _dragHandle(ThemeData theme, int index) =>
      ReorderableDragStartListener(
        index: index,
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          child: Icon(Icons.drag_indicator,
              color: theme.colorScheme.onSurfaceVariant),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Belt and braces: the server withholds drafts from viewers, but a stale
    // cached copy could still carry them.
    final visibleStays = (readOnly ? stays.where((a) => !a.auto) : stays)
        .toList(growable: false);
    final visibleSegments =
        (readOnly ? segments.where((s) => !s.auto) : segments)
            .toList(growable: false);
    final draftCardColor = theme.colorScheme.surfaceContainerLow;
    final canDragStays =
        onReorderStays != null && !readOnly && visibleStays.length > 1;
    final canDragSegments =
        onReorderSegments != null && !readOnly && visibleSegments.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your bookings', style: theme.textTheme.titleMedium),
            ),
            if (!readOnly) ...[
              TextButton.icon(
                onPressed: onAddStay,
                icon: const Icon(Icons.hotel_outlined, size: 18),
                label: const Text('Add stay'),
              ),
              TextButton.icon(
                onPressed: onAddSegment,
                icon: const Icon(Icons.route_outlined, size: 18),
                label: const Text('Add transport'),
              ),
            ],
          ],
        ),
        if (visibleStays.isEmpty && visibleSegments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'Nothing saved yet — add the stay or transport you booked so '
              'the whole trip lives in one place.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        // Only built when non-empty: ReorderableListView is itself a scroll
        // view, and a pair of always-present empty ones would pollute the
        // page's scrollable tree (and every find.byType(CustomScrollView)).
        if (visibleStays.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: visibleStays.length,
            onReorder: (oldIndex, newIndex) =>
                onReorderStays?.call(oldIndex, newIndex),
            itemBuilder: (context, i) {
              final a = visibleStays[i];
              return Card(
                key: ValueKey(a.id),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                color: a.auto ? draftCardColor : null,
                child: ListTile(
                  leading: const Icon(Icons.hotel_outlined),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(a.name,
                            style: _bookedTitleStyle(theme, a.booked)),
                      ),
                      if (a.auto) _suggestedPill(theme),
                    ],
                  ),
                  subtitle: Text(
                    [
                      if (a.provider != null && a.provider!.isNotEmpty)
                        a.provider,
                      if (a.checkIn != null && a.checkOut != null)
                        '${a.checkIn} → ${a.checkOut}',
                      if (a.address != null && a.address!.isNotEmpty) a.address,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: a.auto && !readOnly
                      ? _draftActions(
                          onKeep: () => onConfirmStay(a),
                          onEdit: () => onEditStay(a),
                          onDismiss: () => onDeleteStay(a),
                          dragHandle:
                              canDragStays ? _dragHandle(theme, i) : null,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (a.url != null && a.url!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                tooltip: 'Open listing',
                                onPressed: () => _open(context, a.url!,
                                    provider: a.provider, kind: 'stay'),
                              ),
                            if (!readOnly) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Edit stay',
                                onPressed: () => onEditStay(a),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'Remove stay',
                                onPressed: () => onDeleteStay(a),
                              ),
                            ],
                            _bookedCheckbox(
                              value: a.booked,
                              onChanged:
                                  (readOnly || onStayBookedChanged == null)
                                      ? null
                                      : (v) => onStayBookedChanged!(a, v),
                            ),
                            if (canDragStays) _dragHandle(theme, i),
                          ],
                        ),
                ),
              );
            },
          ),
        if (visibleSegments.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: visibleSegments.length,
            onReorder: (oldIndex, newIndex) =>
                onReorderSegments?.call(oldIndex, newIndex),
            itemBuilder: (context, i) {
              final s = visibleSegments[i];
              return Card(
                key: ValueKey(s.id),
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                color: s.auto ? draftCardColor : null,
                child: ListTile(
                  leading: Icon(_modeIcon(s.mode)),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          [s.origin, s.destination]
                              .whereType<String>()
                              .join(' → '),
                          style: _bookedTitleStyle(theme, s.booked),
                        ),
                      ),
                      if (s.auto) _suggestedPill(theme),
                    ],
                  ),
                  subtitle: Text(
                    [
                      s.mode,
                      if (s.departDate != null) s.departDate,
                      if (s.provider != null && s.provider!.isNotEmpty)
                        s.provider,
                      if (s.notes != null && s.notes!.isNotEmpty) s.notes,
                    ].whereType<String>().join(' · '),
                  ),
                  trailing: s.auto && !readOnly
                      ? _draftActions(
                          onKeep: () => onConfirmSegment(s),
                          onEdit: () => onEditSegment(s),
                          onDismiss: () => onDeleteSegment(s),
                          dragHandle:
                              canDragSegments ? _dragHandle(theme, i) : null,
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (s.url != null && s.url!.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                tooltip: 'Open booking',
                                onPressed: () => _open(context, s.url!,
                                    provider: s.provider, kind: 'transport'),
                              ),
                            if (!readOnly) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                tooltip: 'Edit transport',
                                onPressed: () => onEditSegment(s),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 18),
                                tooltip: 'Remove transport',
                                onPressed: () => onDeleteSegment(s),
                              ),
                            ],
                            _bookedCheckbox(
                              value: s.booked,
                              onChanged:
                                  (readOnly || onSegmentBookedChanged == null)
                                      ? null
                                      : (v) => onSegmentBookedChanged!(s, v),
                            ),
                            if (canDragSegments) _dragHandle(theme, i),
                          ],
                        ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Bottom-sheet form for adding or editing a stay. Pops with the POST/PATCH
/// body map or null. With [initial] set the fields prefill and the labels flip
/// to editing.
class AddStaySheet extends StatefulWidget {
  final Accommodation? initial;
  const AddStaySheet({super.key, this.initial});

  @override
  State<AddStaySheet> createState() => _AddStaySheetState();
}

class _AddStaySheetState extends State<AddStaySheet> {
  final _name = TextEditingController();
  final _provider = TextEditingController();
  final _url = TextEditingController();
  final _address = TextEditingController();
  final _priceNote = TextEditingController();
  DateTime? _checkIn;
  DateTime? _checkOut;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    if (a != null) {
      _name.text = a.name;
      _provider.text = a.provider ?? '';
      _url.text = a.url ?? '';
      _address.text = a.address ?? '';
      _priceNote.text = a.priceNote ?? '';
      _checkIn = a.checkIn == null ? null : DateTime.tryParse(a.checkIn!);
      _checkOut = a.checkOut == null ? null : DateTime.tryParse(a.checkOut!);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _provider, _url, _address, _priceNote]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (range != null) {
      setState(() {
        _checkIn = range.start;
        _checkOut = range.end;
      });
    }
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(<String, dynamic>{
      'name': name,
      if (_provider.text.trim().isNotEmpty) 'provider': _provider.text.trim(),
      if (_url.text.trim().isNotEmpty) 'url': _url.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_priceNote.text.trim().isNotEmpty)
        'price_note': _priceNote.text.trim(),
      if (_checkIn != null) 'check_in': _fmt(_checkIn!),
      if (_checkOut != null) 'check_out': _fmt(_checkOut!),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit stay' : 'Add a stay',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _provider,
              decoration: const InputDecoration(
                labelText: 'Provider (Airbnb, Booking.com, …)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Listing URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Address',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      _checkIn != null && _checkOut != null
                          ? '${_fmt(_checkIn!)} → ${_fmt(_checkOut!)}'
                          : 'Check-in / check-out',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _priceNote,
              decoration: const InputDecoration(
                labelText: 'Price note (e.g. €120/night)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _save,
                  child: Text(editing ? 'Save' : 'Add stay'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet form for adding or editing a transport segment. Pops with the
/// POST/PATCH body map or null. With [initial] set the fields prefill and the
/// labels flip to editing.
class AddSegmentSheet extends StatefulWidget {
  final TripSegment? initial;
  const AddSegmentSheet({super.key, this.initial});

  @override
  State<AddSegmentSheet> createState() => _AddSegmentSheetState();
}

class _AddSegmentSheetState extends State<AddSegmentSheet> {
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _provider = TextEditingController();
  final _url = TextEditingController();
  final _notes = TextEditingController();
  String _mode = 'flight';
  DateTime? _departDate;

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s != null) {
      _origin.text = s.origin ?? '';
      _destination.text = s.destination ?? '';
      _provider.text = s.provider ?? '';
      _url.text = s.url ?? '';
      _notes.text = s.notes ?? '';
      _mode = s.mode;
      _departDate =
          s.departDate == null ? null : DateTime.tryParse(s.departDate!);
    }
  }

  @override
  void dispose() {
    for (final c in [_origin, _destination, _provider, _url, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _departDate = picked);
  }

  void _save() {
    final origin = _origin.text.trim();
    final destination = _destination.text.trim();
    if (origin.isEmpty || destination.isEmpty) return;
    Navigator.of(context).pop(<String, dynamic>{
      'mode': _mode,
      'origin': origin,
      'destination': destination,
      if (_departDate != null) 'depart_date': _fmt(_departDate!),
      if (_provider.text.trim().isNotEmpty) 'provider': _provider.text.trim(),
      if (_url.text.trim().isNotEmpty) 'url': _url.text.trim(),
      if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Edit transport' : 'Add transport',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const [
                  'flight',
                  'train',
                  'bus',
                  'car',
                  'ferry',
                  'other',
                ])
                  ChoiceChip(
                    label: Text(m),
                    selected: _mode == m,
                    onSelected: (_) => setState(() => _mode = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _origin,
                    decoration: const InputDecoration(
                      labelText: 'From *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _destination,
                    decoration: const InputDecoration(
                      labelText: 'To *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.today, size: 18),
              label: Text(
                _departDate != null ? _fmt(_departDate!) : 'Departure date',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _provider,
              decoration: const InputDecoration(
                labelText: 'Provider / carrier',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                labelText: 'Booking URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _save,
                  child: Text(editing ? 'Save' : 'Add transport'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
