import 'package:flutter/material.dart';
import '../models/flight_leg.dart';
import '../models/flight_offer.dart';
import '../utils/tracked_launch.dart';
import 'airline_logo.dart';

/// Opens a modal bottom sheet with the segment-by-segment breakdown of [offer]:
/// each leg's carrier/flight number and depart→arrive clock times, plus the
/// connecting airport and layover duration between consecutive legs.
///
/// Layovers are computed from two timestamps at the *same* airport
/// (`segments[i].arriveTime` and `segments[i+1].departTime`), so they are
/// timezone-safe. We deliberately do not show a per-leg flight duration: the
/// ISO8601 segment times carry no offset and crossing timezones would be wrong —
/// total duration comes from the API via [FlightOffer.durationLabel].
Future<void> showFlightDetails(BuildContext context, FlightOffer offer) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _FlightDetailsSheet(offer: offer),
  );
}

class _FlightDetailsSheet extends StatelessWidget {
  final FlightOffer offer;
  const _FlightDetailsSheet({required this.offer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = offer.segments;
    final from = segments.isNotEmpty ? segments.first.from : '';
    final to = segments.isNotEmpty ? segments.last.to : '';

    // One-way: a flat segment list. Round-trip: an Outbound and a Return
    // section, each with its own duration/stops summary.
    final rows = <Widget>[];
    if (offer.isRoundTrip) {
      rows.add(_DirectionHeader(
          label: 'Outbound',
          detail: '${offer.durationLabel} · ${offer.stopsLabel}'));
      rows.addAll(_sliceRows(offer.segments));
      rows.add(const Divider(height: 24));
      rows.add(_DirectionHeader(
          label: 'Return',
          detail: '${offer.returnDurationLabel} · ${offer.returnStopsLabel}'));
      rows.addAll(_sliceRows(offer.returnSegments));
    } else {
      rows.addAll(_sliceRows(segments));
    }

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AirlineLogo(url: offer.airlineLogoUrl, size: 28),
                  if (offer.airlineLogoUrl != null &&
                      offer.airlineLogoUrl!.isNotEmpty)
                    const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      offer.isRoundTrip ? '$from ⇄ $to' : '$from → $to',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                offer.isRoundTrip
                    ? 'Round trip'
                    : '${offer.durationLabel} · ${offer.stopsLabel}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 24),
              ...rows,
              if (offer.bookingUrl != null) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _book(context, offer.bookingUrl!),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(offer.airlines.isEmpty
                        ? 'Book this flight'
                        : 'Book with ${offer.airlines.first}'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Segment rows for one slice, with layover rows between consecutive legs.
List<Widget> _sliceRows(List<FlightLeg> segments) {
  final rows = <Widget>[];
  for (var i = 0; i < segments.length; i++) {
    rows.add(_SegmentRow(leg: segments[i]));
    if (i < segments.length - 1) {
      rows.add(_LayoverRow(
        airport: segments[i].to,
        duration: _layover(segments[i], segments[i + 1]),
      ));
    }
  }
  return rows;
}

/// Section header for one direction of a round trip, e.g.
/// "Outbound · 7h 30m · Nonstop".
class _DirectionHeader extends StatelessWidget {
  final String label;
  final String detail;
  const _DirectionHeader({required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(detail,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// One flown leg: carrier + flight number, then "FROM hh:mm → TO hh:mm (+N)".
class _SegmentRow extends StatelessWidget {
  final FlightLeg leg;
  const _SegmentRow({required this.leg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final bold = theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600);
    final base = theme.textTheme.bodyLarge?.copyWith(color: muted);
    final dayOffset = _dayOffset(leg.departTime, leg.arriveTime);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flight_takeoff,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                _carrierLabel(leg),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text.rich(
              TextSpan(
                style: base,
                children: [
                  TextSpan(text: '${leg.from} '),
                  TextSpan(text: _clock(leg.departTime), style: bold),
                  const TextSpan(text: '  →  '),
                  TextSpan(text: '${leg.to} '),
                  TextSpan(text: _clock(leg.arriveTime), style: bold),
                  if (dayOffset > 0)
                    TextSpan(
                      text: ' +$dayOffset',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Layover row between two legs, e.g. "Layover LIS · 1h 25m".
class _LayoverRow extends StatelessWidget {
  final String airport;
  final Duration? duration;
  const _LayoverRow({required this.airport, required this.duration});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final label = duration == null
        ? 'Layover $airport'
        : 'Layover $airport · ${_hm(duration!)}';
    return Padding(
      padding: const EdgeInsets.only(left: 26, top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.timelapse, size: 16, color: muted),
          const SizedBox(width: 8),
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: muted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

/// Opens the offer's booking link (airline site or airline-filtered Google
/// Flights) in an external tab.
Future<void> _book(BuildContext context, String url) async {
  final ok = await trackedLaunchUrl(context, url,
      provider: 'duffel', surface: 'flight_details');
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Could not open link')));
  }
}

/// "TAP TP204" — carrier name with flight number, de-duplicating when the
/// flight number already starts with the carrier text.
String _carrierLabel(FlightLeg leg) {
  final carrier = leg.carrier.trim();
  final number = leg.flightNumber.trim();
  if (number.isEmpty) return carrier.isEmpty ? 'Flight' : carrier;
  if (carrier.isEmpty) return number;
  return '$carrier $number';
}

/// "hh:mm" for an ISO8601 time, empty if unparseable.
String _clock(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Calendar days a leg's arrival falls after its departure (for the "+N" badge).
int _dayOffset(String depart, String arrive) {
  final d = DateTime.tryParse(depart);
  final a = DateTime.tryParse(arrive);
  if (d == null || a == null) return 0;
  return DateTime(a.year, a.month, a.day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
}

/// Layover between the arrival of [prev] and the departure of [next] — both at
/// the same airport, so the local-time subtraction is correct. Null if either
/// time is unparseable or the gap is negative.
Duration? _layover(FlightLeg prev, FlightLeg next) {
  final arrive = DateTime.tryParse(prev.arriveTime);
  final depart = DateTime.tryParse(next.departTime);
  if (arrive == null || depart == null) return null;
  final gap = depart.difference(arrive);
  return gap.isNegative ? null : gap;
}

/// "Xh Ym" duration label, matching FlightOffer.durationLabel's style.
String _hm(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
