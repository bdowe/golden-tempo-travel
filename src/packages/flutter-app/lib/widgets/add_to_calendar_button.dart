import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/trips_provider.dart';
import '../utils/calendar_links.dart';
import '../utils/share_link.dart';
import '../utils/snack.dart';
import '../utils/tracked_launch.dart';

/// Per-event "Add to calendar" menu: Google Calendar via a prefilled
/// calendar.google.com link (pure URL — works offline-queued and for
/// read-only viewers), Apple Calendar via the token-gated per-event .ics
/// (needs an export token mint, so [appleEnabled] is false for viewers and
/// offline). Only rendered for dated events — call sites gate on the
/// calendar range resolvers.
class AddToCalendarButton extends ConsumerWidget {
  final String tripId;

  /// Server path segment for the .ics endpoint: stay | segment | item.
  final String kind;
  final String eventId;

  /// Analytics kind, matching the bookings naming: stay | transport | item.
  final String analyticsKind;
  final String title;
  final DateTime start;
  final DateTime endExclusive;
  final String? location;
  final String? details;
  final bool appleEnabled;

  const AddToCalendarButton({
    super.key,
    required this.tripId,
    required this.kind,
    required this.eventId,
    required this.analyticsKind,
    required this.title,
    required this.start,
    required this.endExclusive,
    this.location,
    this.details,
    this.appleEnabled = false,
  });

  Future<void> _openGoogle(BuildContext context) async {
    await trackedLaunchUrl(
      context,
      googleCalendarUrl(
        title: title,
        start: start,
        endExclusive: endExclusive,
        location: location,
        details: details,
      ),
      provider: 'google_calendar',
      surface: 'event_calendar',
      tripId: tripId,
      kind: analyticsKind,
    );
  }

  Future<void> _openApple(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(tripsApiServiceProvider);
      final token = await service.mintExportToken(tripId);
      final url =
          exportEventIcsUrl(service.apiClient.baseUrl, token, kind, eventId);
      if (!context.mounted) return;
      await trackedLaunchUrl(
        context,
        url,
        provider: 'apple_calendar',
        surface: 'event_calendar',
        tripId: tripId,
        kind: analyticsKind,
      );
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Could not export the event: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.event_outlined, size: 18),
      tooltip: 'Add to calendar',
      onSelected: (choice) => switch (choice) {
        'google' => _openGoogle(context),
        _ => _openApple(context, ref),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'google',
          child: ListTile(
            leading: Icon(Icons.event_outlined),
            title: Text('Google Calendar'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'apple',
          enabled: appleEnabled,
          child: const ListTile(
            leading: Icon(Icons.event_available_outlined),
            title: Text('Apple Calendar (.ics)'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
