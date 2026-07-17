import 'package:json_annotation/json_annotation.dart';

part 'price_alert.g.dart';

/// A watched flight route (specs/price-alerts). `targetPrice` null means
/// any-drop mode. `lastNotifiedAt` non-null means the price dropped at least
/// once since creation.
@JsonSerializable()
class PriceAlert {
  final String id;
  final String origin;
  final String destination;
  @JsonKey(name: 'depart_date')
  final String departDate;
  @JsonKey(name: 'return_date')
  final String? returnDate;
  @JsonKey(name: 'cabin_class')
  final String cabinClass;
  final int adults;
  @JsonKey(name: 'target_price')
  final double? targetPrice;

  /// Departure-window half-width (0–3). 0 is the exact-date default; N>0
  /// watches [depart-N, depart+N] for the cheapest day.
  @JsonKey(name: 'flex_days')
  final int flexDays;

  /// Baggage tier the watched search was made with; the checker tracks the
  /// effective price (fare + bag fee) for it.
  @JsonKey(defaultValue: 'personal_item')
  final String baggage; // personal_item | carry_on | checked
  final String? currency;
  @JsonKey(name: 'baseline_price')
  final double? baselinePrice;
  @JsonKey(name: 'last_checked_price')
  final double? lastCheckedPrice;
  @JsonKey(name: 'last_checked_at')
  final String? lastCheckedAt;
  @JsonKey(name: 'last_notified_price')
  final double? lastNotifiedPrice;
  @JsonKey(name: 'last_notified_at')
  final String? lastNotifiedAt;
  final String status; // active | paused | expired
  @JsonKey(name: 'trip_id')
  final String? tripId;
  @JsonKey(name: 'created_at')
  final String createdAt;

  const PriceAlert({
    required this.id,
    required this.origin,
    required this.destination,
    required this.departDate,
    this.returnDate,
    this.cabinClass = 'economy',
    this.adults = 1,
    this.targetPrice,
    this.flexDays = 0,
    this.baggage = 'personal_item',
    this.currency,
    this.baselinePrice,
    this.lastCheckedPrice,
    this.lastCheckedAt,
    this.lastNotifiedPrice,
    this.lastNotifiedAt,
    this.status = 'active',
    this.tripId,
    this.createdAt = '',
  });

  bool get isAnyDrop => targetPrice == null;
  bool get hasTriggered => lastNotifiedAt != null;

  factory PriceAlert.fromJson(Map<String, dynamic> json) =>
      _$PriceAlertFromJson(json);
  Map<String, dynamic> toJson() => _$PriceAlertToJson(this);
}
