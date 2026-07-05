import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/airport.dart';
import '../models/flight_search_request.dart';
import '../providers/flights_provider.dart';
import '../providers/preferences_provider.dart';
import '../widgets/airport_field.dart';
import '../widgets/flight_offer_card.dart';
import '../widgets/gradient_app_bar.dart';

/// Standalone flight search: pick origin/destination/date/passengers and a
/// ranking preset, then browse offers ranked by the Duffel-backed API.
///
/// Optional prefill ([prefillOrigin]/[prefillDestination] may be an IATA code or
/// a city name; [prefillDepartDate] is YYYY-MM-DD) lets callers (e.g. a trip's
/// flight booking item) open the screen ready to search. Prefill takes
/// precedence over the saved home-airport origin seed.
class FlightSearchScreen extends ConsumerStatefulWidget {
  final String? prefillOrigin;
  final String? prefillDestination;
  final String? prefillDepartDate;

  /// Optional coordinates for the prefilled origin/destination. When the name
  /// has no IATA match (e.g. a village like Imerovigli), these resolve to the
  /// nearest bookable airport (e.g. Santorini/JTR).
  final ({double lat, double lng})? prefillOriginCoord;
  final ({double lat, double lng})? prefillDestinationCoord;

  const FlightSearchScreen({
    super.key,
    this.prefillOrigin,
    this.prefillDestination,
    this.prefillDepartDate,
    this.prefillOriginCoord,
    this.prefillDestinationCoord,
  });

  @override
  ConsumerState<FlightSearchScreen> createState() => _FlightSearchScreenState();
}

class _FlightSearchScreenState extends ConsumerState<FlightSearchScreen> {
  Airport? _origin;
  Airport? _destination;
  DateTime? _departDate;
  int _adults = 1;
  int _children = 0;
  String _cabinClass = 'economy';
  String _optimizeFor = 'balanced';

  static const _cabinLabels = {
    'economy': 'Economy',
    'premium_economy': 'Premium economy',
    'business': 'Business',
    'first': 'First',
  };

  static const _presets = {
    'cost': 'Cheapest',
    'time': 'Fastest',
    'balanced': 'Balanced',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedInitial());
  }

  /// Seeds the form from explicit prefill (origin/destination/date) when given,
  /// otherwise falls back to the saved home airport for the origin. Both are
  /// still editable.
  Future<void> _seedInitial() async {
    final w = widget;
    final date = w.prefillDepartDate == null
        ? null
        : DateTime.tryParse(w.prefillDepartDate!);
    if (date != null && _departDate == null) {
      setState(() => _departDate = date);
    }

    // Resolve origin and destination concurrently so a slow/failed lookup on one
    // side doesn't delay or blank the other. Each result is applied on its own.
    final originFuture = (w.prefillOrigin != null && w.prefillOrigin!.isNotEmpty)
        ? _resolve(w.prefillOrigin!, coord: w.prefillOriginCoord)
        : _homeAirportSeed();
    final destFuture =
        (w.prefillDestination != null && w.prefillDestination!.isNotEmpty)
            ? _resolve(w.prefillDestination!, coord: w.prefillDestinationCoord)
            : Future<Airport?>.value(null);

    final resolved = await Future.wait([originFuture, destFuture]);
    final origin = resolved[0];
    final dest = resolved[1];
    if (origin != null && _origin == null && mounted) {
      setState(() => _origin = origin);
    }
    if (dest != null && _destination == null && mounted) {
      setState(() => _destination = dest);
    }

    // Run the search as soon as it's runnable (both endpoints resolved + a date),
    // regardless of which inputs were prefilled vs. seeded — so the caller lands
    // on results without tapping Search.
    if (mounted && _canSearch) _search();
  }

  /// Falls back to the traveler's saved home airport when no explicit origin was
  /// prefilled. Returns null when none is set.
  Future<Airport?> _homeAirportSeed() async {
    await ref.read(preferencesProvider.notifier).load();
    final code = ref.read(preferencesProvider).prefs?.homeAirport;
    if (code == null || code.isEmpty) return null;
    return Airport(iataCode: code, name: code);
  }

  /// Resolves an IATA code or city name to an [Airport]. A 3-letter alphabetic
  /// input is used as-is; otherwise the Duffel airport search resolves it. When
  /// the raw label finds nothing (e.g. a label with a postal/qualifier prefix),
  /// it retries once with a cleaned query, then — if [coord] is given — falls
  /// back to the nearest airport by coordinate (e.g. a village -> its island
  /// airport). Mirrors the backend's resolveIATA.
  Future<Airport?> _resolve(String query, {({double lat, double lng})? coord}) async {
    final q = query.trim();
    final isCode = q.length == 3 && RegExp(r'^[A-Za-z]{3}$').hasMatch(q);
    if (isCode) return Airport(iataCode: q.toUpperCase(), name: q.toUpperCase());

    final cleaned = _cleanLabel(q);
    final attempts = <String>[q, if (cleaned != q) cleaned];
    for (final attempt in attempts) {
      final hit = await _lookupAirport(attempt);
      if (hit != null) return hit;
    }
    if (coord != null) return _nearestAirport(coord.lat, coord.lng);
    return null;
  }

  /// Looks up the nearest bookable airport to a coordinate. Returns null on
  /// empty results or any error.
  Future<Airport?> _nearestAirport(double lat, double lng) async {
    try {
      final results =
          await ref.read(flightsApiServiceProvider).nearestAirports(lat, lng);
      return results.isEmpty ? null : results.first;
    } catch (_) {
      return null;
    }
  }

  /// Runs one airport lookup, preferring an `airport`-type result over a `city`
  /// (so we book against a concrete airport when the typeahead returns both).
  /// Returns null on empty results or any error so the caller can retry/fall back.
  Future<Airport?> _lookupAirport(String query) async {
    try {
      final results =
          await ref.read(flightsApiServiceProvider).searchAirports(query);
      if (results.isEmpty) return null;
      return results.firstWhere(
        (a) => a.subType.toLowerCase() == 'airport',
        orElse: () => results.first,
      );
    } catch (_) {
      return null;
    }
  }

  /// Drops any trailing qualifier after a comma and collapses a leading
  /// postal/qualifier token, e.g. "1400 Lisboa, Portugal" -> "Lisboa".
  String _cleanLabel(String label) {
    var s = label.split(',').first.trim();
    final tokens = s.split(RegExp(r'\s+'));
    if (tokens.length > 1 && RegExp(r'\d').hasMatch(tokens.first)) {
      s = tokens.sublist(1).join(' ').trim();
    }
    return s.isEmpty ? label : s;
  }

  bool get _canSearch =>
      _origin != null && _destination != null && _departDate != null;

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _departDate ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _departDate = picked);
  }

  void _search() {
    if (!_canSearch) return;
    ref.read(flightsProvider.notifier).search(FlightSearchRequest(
          origin: _origin!.iataCode,
          destination: _destination!.iataCode,
          departDate: _fmtDate(_departDate!),
          adults: _adults,
          // Duffel needs an age per child; without a per-child age picker we
          // send a mid-range child age for each.
          childAges:
              _children > 0 ? List.filled(_children, 8) : null,
          cabinClass: _cabinClass == 'economy' ? null : _cabinClass,
          optimizeFor: _optimizeFor,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(flightsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const GradientAppBar(title: Text('Find Flights')),
      body: Column(
        children: [
          // Search form
          Container(
            color: theme.colorScheme.surface,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                AirportField(
                  label: 'From',
                  icon: Icons.flight_takeoff,
                  selected: _origin,
                  onSelected: (a) => setState(() => _origin = a),
                ),
                const SizedBox(height: 12),
                AirportField(
                  label: 'To',
                  icon: Icons.flight_land,
                  selected: _destination,
                  onSelected: (a) => setState(() => _destination = a),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(_departDate == null
                            ? 'Departure date'
                            : _fmtDate(_departDate!)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _PassengerStepper(
                      icon: Icons.person_outline,
                      count: _adults,
                      min: 1,
                      onChanged: (v) => setState(() => _adults = v),
                    ),
                    const SizedBox(width: 8),
                    _PassengerStepper(
                      icon: Icons.child_care_outlined,
                      count: _children,
                      min: 0,
                      onChanged: (v) => setState(() => _children = v),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final e in _cabinLabels.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: _cabinClass == e.key,
                          onSelected: (_) =>
                              setState(() => _cabinClass = e.key),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: _presets.entries
                      .map((e) => ButtonSegment(
                            value: e.key,
                            label: Text(e.value),
                          ))
                      .toList(),
                  selected: {_optimizeFor},
                  onSelectionChanged: (s) =>
                      setState(() => _optimizeFor = s.first),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _canSearch && !state.loading ? _search : null,
                    icon: state.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search),
                    label: Text(state.loading ? 'Searching…' : 'Search Flights'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(child: _Results(state: state)),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  final FlightsState state;
  const _Results({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('Could not load flights',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (!state.hasSearched) {
      return _Hint(
        icon: Icons.flight,
        text: 'Choose an origin, destination, and date to find flights.',
      );
    }

    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.offers.isEmpty) {
      return const _Hint(
        icon: Icons.search_off,
        text: 'No flights found for this route and date.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: state.offers.length,
      itemBuilder: (context, i) {
        final offer = state.offers[i];
        return FlightOfferCard(
          offer: offer,
          isBest: offer.id == state.bestOfferId,
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _PassengerStepper extends StatelessWidget {
  final IconData icon;
  final int count;
  final int min;
  final ValueChanged<int> onChanged;
  const _PassengerStepper({
    required this.icon,
    required this.count,
    required this.min,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(icon, size: 16),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            onPressed: count > min ? () => onChanged(count - 1) : null,
            visualDensity: VisualDensity.compact,
          ),
          Text('$count',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: count < 8 ? () => onChanged(count + 1) : null,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

