import 'package:json_annotation/json_annotation.dart';

part 'itinerary_item.g.dart';

@JsonSerializable()
class ItineraryItem {
  final String id;
  final int position;
  final String name;
  @JsonKey(name: 'place_id')
  final String? placeId;
  final String? address;
  final double latitude;
  final double longitude;
  final String? category;
  @JsonKey(name: 'time_of_day')
  final String? timeOfDay;
  final String? city;
  @JsonKey(name: 'day_trip_from')
  final String? dayTripFrom;
  final int? day;

  /// Local-source attribution snapshots: the name of the local who recommended
  /// this place and the recommendation pin it came from. Write-once at item
  /// creation (agent or add-to-trip); survive pin archival by design.
  @JsonKey(name: 'local_source_name')
  final String? localSourceName;
  @JsonKey(name: 'local_recommendation_id')
  final String? localRecommendationId;

  const ItineraryItem({
    required this.id,
    required this.position,
    required this.name,
    this.placeId,
    this.address,
    required this.latitude,
    required this.longitude,
    this.category,
    this.timeOfDay,
    this.city,
    this.dayTripFrom,
    this.day,
    this.localSourceName,
    this.localRecommendationId,
  });

  factory ItineraryItem.fromJson(Map<String, dynamic> json) =>
      _$ItineraryItemFromJson(json);
  Map<String, dynamic> toJson() => _$ItineraryItemToJson(this);
}
