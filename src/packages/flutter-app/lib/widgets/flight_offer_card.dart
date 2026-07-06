import 'package:flutter/material.dart';
import '../models/flight_offer.dart';
import '../utils/tracked_launch.dart';
import 'airline_logo.dart';
import 'flight_details_sheet.dart';

/// A single ranked flight offer rendered as a card — airline(s), route, price,
/// score, duration/stops, and a Book deep-link. Shared by the standalone
/// FlightSearchScreen and the AI agent chat. Set [isBest] to highlight the top
/// pick with a teal border and "BEST MATCH" badge.
class FlightOfferCard extends StatelessWidget {
  final FlightOffer offer;
  final bool isBest;
  const FlightOfferCard({super.key, required this.offer, this.isBest = false});

  Future<void> _book(BuildContext context) async {
    final url = offer.bookingUrl;
    if (url == null || url.isEmpty) return;
    final ok = await trackedLaunchUrl(context, url,
        provider: 'duffel', surface: 'flight_card');
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Colors.teal.shade700;

    return Card(
      elevation: isBest ? 4 : 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isBest ? BorderSide(color: accent, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => showFlightDetails(context, offer),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isBest)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('BEST MATCH',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AirlineLogo(url: offer.airlineLogoUrl, size: 22),
                            if (offer.airlineLogoUrl != null &&
                                offer.airlineLogoUrl!.isNotEmpty)
                              const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                offer.airlines.isEmpty
                                    ? 'Flight'
                                    : offer.airlines.join(', '),
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        if (offer.segments.isNotEmpty) _Times(offer: offer),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${offer.currency} ${offer.price.toStringAsFixed(0)}',
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold, color: accent),
                      ),
                      Text('score ${offer.score.toStringAsFixed(1)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(icon: Icons.schedule, label: offer.durationLabel),
                  const SizedBox(width: 16),
                  _Stat(
                      icon: Icons.connecting_airports, label: offer.stopsLabel),
                  if (offer.stops > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right,
                        size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ],
                  const Spacer(),
                  if (offer.bookingUrl != null)
                    TextButton.icon(
                      onPressed: () => _book(context),
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Book'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Route line with departure/arrival clock times, e.g. "EWR 10:50 → GIG 00:47 +1".
class _Times extends StatelessWidget {
  final FlightOffer offer;
  const _Times({required this.offer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final from = offer.segments.first.from;
    final to = offer.segments.last.to;
    final bold = theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600);
    final base = theme.textTheme.bodyMedium?.copyWith(color: muted);

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: '$from '),
          if (offer.departClock.isNotEmpty)
            TextSpan(text: offer.departClock, style: bold),
          const TextSpan(text: '  →  '),
          TextSpan(text: '$to '),
          if (offer.arriveClock.isNotEmpty)
            TextSpan(text: offer.arriveClock, style: bold),
          if (offer.arrivalDayOffset > 0)
            TextSpan(
              text: ' +${offer.arrivalDayOffset}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Stat({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}
