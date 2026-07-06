import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/analytics_provider.dart';

/// The single pathway for opening an outbound booking/provider link: records a
/// `booking_link_clicked` analytics event (the attach-rate numerator,
/// specs/instrumentation-events) and then launches [url] externally.
///
/// Recording is strictly fire-and-forget — an analytics failure (or a widget
/// tree without a ProviderScope) must never block, delay, or break the launch.
/// Returns whether the launch succeeded, so call sites can keep their own
/// "Could not open link" handling.
///
/// Signed-out clicks are recorded too: `booking_link_clicked` is on the API's
/// anonymous whitelist, so the service sends it without an Authorization
/// header (the server stores it with a NULL user id and drops any trip_id).
///
/// [provider] is who the user is being handed to (duffel, ferryhopper,
/// ticketmaster, booking.com, airbnb, …) and [surface] is which UI element the
/// click came from (booking_checklist, flight_card, chat, …). Keep both short:
/// the API caps event metadata at 2KB.
Future<bool> trackedLaunchUrl(
  BuildContext context,
  String url, {
  required String provider,
  required String surface,
  String? tripId,
  String? todoKey,
  String? kind,
}) async {
  final uri = Uri.tryParse(url);
  if (url.isEmpty || uri == null) return false;
  trackBookingLinkClick(
    context,
    provider: provider,
    surface: surface,
    tripId: tripId,
    todoKey: todoKey,
    kind: kind,
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Records the booking-click event without launching anything — for the rare
/// booking handoff that stays in-app (e.g. the checklist's prefilled Find
/// Flights screen). External links should use [trackedLaunchUrl] instead.
void trackBookingLinkClick(
  BuildContext context, {
  required String provider,
  required String surface,
  String? tripId,
  String? todoKey,
  String? kind,
}) {
  try {
    ProviderScope.containerOf(context, listen: false)
        .read(analyticsApiServiceProvider)
        .recordBookingLinkClicked(
          tripId: tripId,
          todoKey: todoKey,
          provider: provider,
          surface: surface,
          kind: kind,
        );
  } catch (_) {
    // Tracking must never break the user's action.
  }
}
