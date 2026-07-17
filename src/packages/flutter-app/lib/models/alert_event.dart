import 'package:json_annotation/json_annotation.dart';

part 'alert_event.g.dart';

/// One durable price-drop notification (specs/price-alerts-v2). Written by the
/// checker when an alert triggers; the alert's route/dates are joined in so a
/// feed row renders without a second request. `readAt == null` means unread.
@JsonSerializable()
class AlertEvent {
  final String id;
  @JsonKey(name: 'alert_id')
  final String alertId;
  final double price;
  final String currency;

  /// The reference price the drop was judged against — absent when a
  /// target-mode alert triggers on its very first observation.
  @JsonKey(name: 'previous_price')
  final double? previousPrice;
  @JsonKey(name: 'occurred_at')
  final String occurredAt;
  @JsonKey(name: 'read_at')
  final String? readAt;
  final String origin;
  final String destination;
  @JsonKey(name: 'depart_date')
  final String departDate;
  @JsonKey(name: 'return_date')
  final String? returnDate;
  @JsonKey(name: 'target_price')
  final double? targetPrice;
  @JsonKey(name: 'alert_status')
  final String alertStatus;

  const AlertEvent({
    required this.id,
    required this.alertId,
    required this.price,
    required this.currency,
    this.previousPrice,
    required this.occurredAt,
    this.readAt,
    required this.origin,
    required this.destination,
    required this.departDate,
    this.returnDate,
    this.targetPrice,
    required this.alertStatus,
  });

  bool get isUnread => readAt == null;

  factory AlertEvent.fromJson(Map<String, dynamic> json) =>
      _$AlertEventFromJson(json);
  Map<String, dynamic> toJson() => _$AlertEventToJson(this);
}
