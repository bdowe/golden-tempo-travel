import 'package:json_annotation/json_annotation.dart';
import 'flight_leg.dart';

part 'flight_offer.g.dart';

@JsonSerializable(explicitToJson: true)
class FlightOffer {
  final String id;
  final double price;
  final String currency;
  final int stops;
  @JsonKey(name: 'duration_minutes')
  final int durationMinutes;
  @JsonKey(defaultValue: <String>[])
  final List<String> airlines;
  @JsonKey(name: 'airline_code')
  final String? airlineCode;
  @JsonKey(name: 'airline_logo_url')
  final String? airlineLogoUrl;
  @JsonKey(name: 'depart_time')
  final String departTime;
  @JsonKey(name: 'arrive_time')
  final String arriveTime;
  @JsonKey(defaultValue: <FlightLeg>[])
  final List<FlightLeg> segments;
  @JsonKey(name: 'booking_url')
  final String? bookingUrl;

  /// Round-trip only: the return slice's legs and duration (empty/zero for
  /// one-way offers). [price] is always the total across both directions;
  /// [stops]/[durationMinutes]/[departTime]/[arriveTime] stay outbound-based.
  @JsonKey(name: 'return_segments', defaultValue: <FlightLeg>[])
  final List<FlightLeg> returnSegments;
  @JsonKey(name: 'return_duration_minutes', defaultValue: 0)
  final int returnDurationMinutes;

  /// Included baggage per passenger — the worst case across every flown
  /// segment (a bag only counts if every segment grants it).
  @JsonKey(name: 'included_carry_on', defaultValue: 0)
  final int includedCarryOn;
  @JsonKey(name: 'included_checked', defaultValue: 0)
  final int includedChecked;

  /// Effective pricing, present only on carry-on/checked searches:
  /// "included" | "paid" | "unknown".
  @JsonKey(name: 'baggage_status')
  final String? baggageStatus;
  @JsonKey(name: 'bag_fee', defaultValue: 0)
  final double bagFee;
  @JsonKey(name: 'effective_price')
  final double? effectivePrice;

  final double score;
  @JsonKey(name: 'price_score')
  final double priceScore;
  @JsonKey(name: 'duration_score')
  final double durationScore;
  @JsonKey(name: 'stops_score')
  final double stopsScore;

  const FlightOffer({
    required this.id,
    required this.price,
    required this.currency,
    required this.stops,
    required this.durationMinutes,
    required this.airlines,
    this.airlineCode,
    this.airlineLogoUrl,
    required this.departTime,
    required this.arriveTime,
    required this.segments,
    this.bookingUrl,
    this.includedCarryOn = 0,
    this.includedChecked = 0,
    this.baggageStatus,
    this.bagFee = 0,
    this.effectivePrice,
    this.returnSegments = const [],
    this.returnDurationMinutes = 0,
    this.score = 0,
    this.priceScore = 0,
    this.durationScore = 0,
    this.stopsScore = 0,
  });

  /// The price to show the traveler: the effective total (fare + bag fee)
  /// on baggage-aware searches, the bare fare otherwise.
  double get displayPrice => effectivePrice ?? price;

  /// True when a needed bag couldn't be priced — the fare shown understates
  /// the real cost.
  bool get bagFeeUnknown => baggageStatus == 'unknown';

  /// True when the offer carries a return slice (round-trip search).
  bool get isRoundTrip => returnSegments.isNotEmpty;

  /// Stops on the return slice (0 when one-way or nonstop).
  int get returnStops => returnSegments.isEmpty ? 0 : returnSegments.length - 1;

  /// "5h 30m" style duration label for the outbound slice.
  String get durationLabel => _fmtDuration(durationMinutes);

  /// "5h 30m" style duration label for the return slice.
  String get returnDurationLabel => _fmtDuration(returnDurationMinutes);

  // Stop-count labels are prose and live in utils/flight_labels.dart, which
  // can pluralize per locale (specs/i18n-spanish). Duration labels stay here:
  // "7h 30m" is a unit abbreviation, not copy.

  static String _fmtDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }


  /// Departure clock time, e.g. "10:50". Empty if unparseable.
  String get departClock => _clock(departTime);

  /// Arrival clock time, e.g. "00:47". Empty if unparseable.
  String get arriveClock => _clock(arriveTime);

  /// How many calendar days after departure the flight arrives (0 = same day,
  /// 1 = next day) — for the "+1" overnight indicator.
  int get arrivalDayOffset {
    final d = DateTime.tryParse(departTime);
    final a = DateTime.tryParse(arriveTime);
    if (d == null || a == null) return 0;
    return DateTime(a.year, a.month, a.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
  }

  static String _clock(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  factory FlightOffer.fromJson(Map<String, dynamic> json) =>
      _$FlightOfferFromJson(json);
  Map<String, dynamic> toJson() => _$FlightOfferToJson(this);
}
