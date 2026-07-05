import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/accommodation.dart';
import '../models/trip.dart';
import '../models/trip_segment.dart';
import '../theme/spacing.dart';

/// "Your bookings" hub in trip detail: the stays and transport segments the
/// user has actually saved (distinct from the auto-derived booking checklist).
/// Add/delete call back into the screen, which persists via the existing
/// accommodations/segments endpoints and reloads the trip.
class BookingsSection extends StatelessWidget {
  final Trip trip;
  final VoidCallback onAddStay;
  final void Function(Accommodation) onDeleteStay;
  final VoidCallback onAddSegment;
  final void Function(TripSegment) onDeleteSegment;

  const BookingsSection({
    super.key,
    required this.trip,
    required this.onAddStay,
    required this.onDeleteStay,
    required this.onAddSegment,
    required this.onDeleteSegment,
  });

  static IconData _modeIcon(String mode) => switch (mode) {
        'flight' => Icons.flight_takeoff,
        'train' => Icons.train_outlined,
        'bus' => Icons.directions_bus_outlined,
        'car' => Icons.directions_car_outlined,
        'ferry' => Icons.directions_boat_outlined,
        _ => Icons.route_outlined,
      };

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stays = trip.accommodations ?? const <Accommodation>[];
    final segments = trip.segments ?? const <TripSegment>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your bookings', style: theme.textTheme.titleMedium),
            ),
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
        ),
        if (stays.isEmpty && segments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'Nothing saved yet — add the stay or transport you booked so '
              'the whole trip lives in one place.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        for (final a in stays)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: const Icon(Icons.hotel_outlined),
              title: Text(a.name),
              subtitle: Text(
                [
                  if (a.provider != null && a.provider!.isNotEmpty) a.provider,
                  if (a.checkIn != null && a.checkOut != null)
                    '${a.checkIn} → ${a.checkOut}',
                  if (a.address != null && a.address!.isNotEmpty) a.address,
                ].whereType<String>().join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (a.url != null && a.url!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'Open listing',
                      onPressed: () => _open(a.url!),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove stay',
                    onPressed: () => onDeleteStay(a),
                  ),
                ],
              ),
            ),
          ),
        for (final s in segments)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              leading: Icon(_modeIcon(s.mode)),
              title: Text(
                [s.origin, s.destination].whereType<String>().join(' → '),
              ),
              subtitle: Text(
                [
                  s.mode,
                  if (s.departDate != null) s.departDate,
                  if (s.provider != null && s.provider!.isNotEmpty) s.provider,
                  if (s.notes != null && s.notes!.isNotEmpty) s.notes,
                ].whereType<String>().join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s.url != null && s.url!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'Open booking',
                      onPressed: () => _open(s.url!),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Remove transport',
                    onPressed: () => onDeleteSegment(s),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Bottom-sheet form for adding a stay. Pops with the POST body map or null.
class AddStaySheet extends StatefulWidget {
  const AddStaySheet({super.key});

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
            Text('Add a stay', style: theme.textTheme.titleMedium),
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
                FilledButton(onPressed: _save, child: const Text('Add stay')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet form for adding a transport segment. Pops with the POST body
/// map or null.
class AddSegmentSheet extends StatefulWidget {
  const AddSegmentSheet({super.key});

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
            Text('Add transport', style: theme.textTheme.titleMedium),
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
                  child: const Text('Add transport'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
