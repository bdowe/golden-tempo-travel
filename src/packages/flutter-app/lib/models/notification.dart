import 'package:json_annotation/json_annotation.dart';

part 'notification.g.dart';

/// One row in the generalized notifications feed (Wave 16). Type-agnostic: the
/// discriminator is [type] and the render data lives in [payload] — a raw JSON
/// map the UI switches on. `readAt == null` means unread. Today the only writer
/// is the price-alert checker (`type == 'price_drop'`); trip reminders,
/// collaborator edits and invite-accepted land here in later waves.
@JsonSerializable()
class AppNotification {
  final String id;
  final String type;

  /// Free-form render data. For `price_drop`: origin, destination, price,
  /// currency, previous_price?, depart_date, return_date?, matched_date?,
  /// target_price?, alert_status, alert_id.
  @JsonKey(defaultValue: <String, dynamic>{})
  final Map<String, dynamic> payload;

  @JsonKey(name: 'trip_id')
  final String? tripId;
  @JsonKey(name: 'read_at')
  final String? readAt;
  @JsonKey(name: 'created_at')
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    this.payload = const <String, dynamic>{},
    this.tripId,
    this.readAt,
    required this.createdAt,
  });

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      _$AppNotificationFromJson(json);
  Map<String, dynamic> toJson() => _$AppNotificationToJson(this);
}
