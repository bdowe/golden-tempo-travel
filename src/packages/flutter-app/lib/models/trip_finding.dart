import 'package:json_annotation/json_annotation.dart';

part 'trip_finding.g.dart';

/// One issue surfaced by the trip-health review (`GET /trips/{id}/review`).
/// [severity] is info | warn | critical; [category] is one of dates |
/// unscheduled | packing | lodging | transit | budget | bookings. [day] and
/// [itemId] are optional deep-link anchors: when present, tapping the finding
/// scrolls the itinerary to that day (or the day of that item).
@JsonSerializable()
class TripFinding {
  final String severity;
  final String category;
  final String message;
  @JsonKey(name: 'trip_id')
  final String tripId;
  final int? day;
  @JsonKey(name: 'item_id')
  final String? itemId;

  const TripFinding({
    required this.severity,
    required this.category,
    required this.message,
    required this.tripId,
    this.day,
    this.itemId,
  });

  factory TripFinding.fromJson(Map<String, dynamic> json) =>
      _$TripFindingFromJson(json);
  Map<String, dynamic> toJson() => _$TripFindingToJson(this);
}
