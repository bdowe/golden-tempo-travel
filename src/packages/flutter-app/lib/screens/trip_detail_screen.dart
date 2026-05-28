import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/trip.dart';
import '../models/airbnb_listing.dart';
import '../providers/trips_provider.dart';
import '../providers/accommodations_provider.dart';
import '../services/accommodations_api_service.dart';
import '../services/airbnb_api_service.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  Trip? _trip;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trip = await ref.read(tripsApiServiceProvider).getTrip(widget.tripId);
      if (mounted) setState(() => _trip = trip);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _patch({String? title, String? startDate, String? endDate, String? status}) async {
    try {
      final updated = await ref.read(tripsApiServiceProvider).patchTrip(
            widget.tripId,
            title: title,
            startDate: startDate,
            endDate: endDate,
            status: status,
          );
      if (mounted) setState(() => _trip = updated);
      ref.read(tripsProvider.notifier).loadTrips(); // keep list in sync
    } catch (e) {
      _showSnack('Update failed: $e');
    }
  }

  Future<void> _editTitle() async {
    final controller = TextEditingController(text: _trip?.title ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit title'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await _patch(title: result);
    }
  }

  Future<void> _editDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (range != null) {
      await _patch(startDate: _fmt(range.start), endDate: _fmt(range.end));
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete trip?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ref.read(tripsProvider.notifier).deleteTrip(widget.tripId);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        _showSnack('Delete failed: $e');
      }
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = _trip;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          if (trip != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete trip',
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Could not load this trip'),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                )
              : trip == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(trip.title, style: theme.textTheme.headlineSmall),
                            ),
                            IconButton(icon: const Icon(Icons.edit), onPressed: _editTitle),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.event, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              (trip.startDate != null && trip.endDate != null)
                                  ? '${trip.startDate} → ${trip.endDate}'
                                  : 'No dates set',
                            ),
                            TextButton(onPressed: _editDates, child: const Text('Edit')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Status:'),
                            const SizedBox(width: 12),
                            DropdownButton<String>(
                              value: trip.status == 'planned' ? 'planned' : 'draft',
                              items: const [
                                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                                DropdownMenuItem(value: 'planned', child: Text('Planned')),
                              ],
                              onChanged: (v) {
                                if (v != null) _patch(status: v);
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 32),
                        Text('Itinerary', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        if ((trip.items ?? []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('No places added.'),
                          )
                        else
                          for (final item in trip.items!)
                            ListTile(
                              leading: CircleAvatar(child: Text('${item.position + 1}')),
                              title: Text(item.name),
                              subtitle: item.address != null ? Text(item.address!) : null,
                            ),
                        const Divider(height: 32),
                        Row(
                          children: [
                            Expanded(child: Text('Stays', style: theme.textTheme.titleMedium)),
                            TextButton.icon(
                              onPressed: () => _findStays(trip),
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('Find stays'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if ((trip.accommodations ?? []).isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('No stays added yet.'),
                          )
                        else
                          for (final acc in trip.accommodations!)
                            ListTile(
                              leading: const Icon(Icons.hotel),
                              title: Text(acc.name),
                              subtitle: Text([
                                if (acc.provider != null) acc.provider!,
                                if (acc.checkIn != null && acc.checkOut != null)
                                  '${acc.checkIn} → ${acc.checkOut}',
                                if (acc.priceNote != null) acc.priceNote!,
                              ].join(' · ')),
                              onTap: acc.url != null ? () => _launch(acc.url!) : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteAccommodation(acc.id),
                              ),
                            ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: _addStay,
                            icon: const Icon(Icons.add),
                            label: const Text('Add a stay'),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Future<void> _launch(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) _showSnack('Could not open link');
  }

  Future<void> _deleteAccommodation(String accId) async {
    try {
      await ref.read(accommodationsApiServiceProvider).delete(widget.tripId, accId);
      await _load();
    } catch (e) {
      _showSnack('Delete failed: $e');
    }
  }

  Future<void> _findStays(Trip trip) async {
    final initial = (trip.items != null && trip.items!.isNotEmpty)
        ? trip.items!.first.name
        : trip.title;
    await showDialog<void>(
      context: context,
      builder: (_) => _FindStaysDialog(
        initialDestination: initial,
        checkIn: trip.startDate,
        checkOut: trip.endDate,
      ),
    );
  }

  Future<void> _addStay() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _AddStayDialog(tripId: widget.tripId),
    );
    if (added == true) await _load();
  }
}

/// Lets the user browse Airbnb + Booking.com for a destination via deep links.
class _FindStaysDialog extends ConsumerStatefulWidget {
  final String initialDestination;
  final String? checkIn;
  final String? checkOut;

  const _FindStaysDialog({required this.initialDestination, this.checkIn, this.checkOut});

  @override
  ConsumerState<_FindStaysDialog> createState() => _FindStaysDialogState();
}

class _FindStaysDialogState extends ConsumerState<_FindStaysDialog> {
  late final TextEditingController _destination =
      TextEditingController(text: widget.initialDestination);
  List<ProviderLink> _links = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _getLinks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await ref.read(accommodationsApiServiceProvider).links(
            destination: _destination.text.trim(),
            checkIn: widget.checkIn,
            checkOut: widget.checkOut,
          );
      setState(() => _links = links);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  String _label(String provider) => provider == 'airbnb'
      ? 'Browse on Airbnb'
      : provider == 'booking'
          ? 'Browse on Booking.com'
          : provider;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Find stays'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _destination,
            decoration: const InputDecoration(labelText: 'Destination'),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final link in _links)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
                  child: Text(_label(link.provider)),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton(
          onPressed: _loading ? null : _getLinks,
          child: _loading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Get links'),
        ),
      ],
    );
  }
}

/// Add a stay manually, optionally pre-filled by parsing a pasted Airbnb URL.
class _AddStayDialog extends ConsumerStatefulWidget {
  final String tripId;
  const _AddStayDialog({required this.tripId});

  @override
  ConsumerState<_AddStayDialog> createState() => _AddStayDialogState();
}

class _AddStayDialogState extends ConsumerState<_AddStayDialog> {
  final _airbnbUrl = TextEditingController();
  final _name = TextEditingController();
  final _priceNote = TextEditingController();
  String? _resolvedUrl;
  String? _provider;
  String? _address;
  double? _lat;
  double? _lng;
  bool _fetching = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _airbnbUrl.dispose();
    _name.dispose();
    _priceNote.dispose();
    super.dispose();
  }

  Future<void> _fetchAirbnb() async {
    final url = _airbnbUrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final apiClient = ref.read(accommodationsApiServiceProvider).apiClient;
      final svc = AirbnbApiService(baseUrl: apiClient.baseUrl, httpClient: apiClient.httpClient);
      final AirbnbListing listing = await svc.parseListing(url);
      setState(() {
        _name.text = listing.title;
        _resolvedUrl = listing.url.isNotEmpty ? listing.url : url;
        _provider = 'airbnb';
        _address = '${listing.location.city}, ${listing.location.country}';
        _lat = listing.location.latitude;
        _lng = listing.location.longitude;
        _priceNote.text =
            '${listing.pricing.currency} ${listing.pricing.nightlyRate.toStringAsFixed(0)}/night';
      });
    } catch (e) {
      setState(() => _error = 'Could not parse that Airbnb link');
    } finally {
      setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accommodationsApiServiceProvider).add(widget.tripId, {
        'name': _name.text.trim(),
        if (_provider != null) 'provider': _provider,
        if (_resolvedUrl != null) 'url': _resolvedUrl,
        if (_address != null) 'address': _address,
        if (_lat != null) 'latitude': _lat,
        if (_lng != null) 'longitude': _lng,
        if (_priceNote.text.trim().isNotEmpty) 'price_note': _priceNote.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Save failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a stay'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _airbnbUrl,
                    decoration: const InputDecoration(labelText: 'Airbnb link (optional)'),
                  ),
                ),
                TextButton(
                  onPressed: _fetching ? null : _fetchAirbnb,
                  child: _fetching
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Fetch'),
                ),
              ],
            ),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: _priceNote, decoration: const InputDecoration(labelText: 'Price note (optional)')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
