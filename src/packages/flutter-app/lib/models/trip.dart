import 'package:json_annotation/json_annotation.dart';
import 'itinerary_item.dart';
import 'accommodation.dart';

part 'trip.g.dart';

@JsonSerializable(explicitToJson: true)
class Trip {
  final String id;
  final String title;
  @JsonKey(name: 'start_date')
  final String? startDate;
  @JsonKey(name: 'end_date')
  final String? endDate;
  final String status;
  @JsonKey(name: 'created_at')
  final String createdAt;
  @JsonKey(name: 'updated_at')
  final String updatedAt;
  final List<ItineraryItem>? items;
  final List<Accommodation>? accommodations;

  const Trip({
    required this.id,
    required this.title,
    this.startDate,
    this.endDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.items,
    this.accommodations,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => _$TripFromJson(json);
  Map<String, dynamic> toJson() => _$TripToJson(this);
}
