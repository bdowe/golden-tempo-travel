import '../l10n/l10n.dart';
import '../models/flight_offer.dart';

/// Stop-count labels for flight offers (specs/i18n-spanish).
///
/// These live here rather than on [FlightOffer] because they are prose, and
/// Spanish pluralizes differently ("1 escala" / "2 escalas") — a model getter
/// returning a fixed English sentence can't express that. Duration labels stay
/// on the model: "7h 30m" is a unit abbreviation, not copy.

/// "Nonstop" / "1 stop" / "N stops".
String stopsLabel(AppLocalizations l10n, int stops) => l10n.flightStops(stops);

/// One label covering both directions of a round trip — "Nonstop",
/// "1 stop each way", or "Nonstop / 1 stop" when the directions differ.
/// Falls back to the one-way label for one-way offers.
String combinedStopsLabel(AppLocalizations l10n, FlightOffer offer) {
  if (!offer.isRoundTrip) return stopsLabel(l10n, offer.stops);
  if (offer.stops == offer.returnStops) {
    return offer.stops == 0
        ? stopsLabel(l10n, 0)
        : l10n.flightStopsEachWay(stopsLabel(l10n, offer.stops));
  }
  return l10n.flightStopsSplit(
      stopsLabel(l10n, offer.stops), stopsLabel(l10n, offer.returnStops));
}
