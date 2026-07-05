import 'package:json_annotation/json_annotation.dart';

part 'flight_search_request.g.dart';

@JsonSerializable()
class FlightSearchRequest {
  final String origin; // IATA code
  final String destination; // IATA code
  @JsonKey(name: 'depart_date')
  final String departDate; // YYYY-MM-DD
  @JsonKey(name: 'return_date', includeIfNull: false)
  final String? returnDate;
  final int adults;
  @JsonKey(name: 'child_ages', includeIfNull: false)
  final List<int>? childAges; // one entry per child (0-17)
  @JsonKey(name: 'cabin_class', includeIfNull: false)
  final String? cabinClass; // economy | premium_economy | business | first
  @JsonKey(name: 'optimize_for')
  final String optimizeFor; // cost | time | balanced

  const FlightSearchRequest({
    required this.origin,
    required this.destination,
    required this.departDate,
    this.returnDate,
    this.adults = 1,
    this.childAges,
    this.cabinClass,
    this.optimizeFor = 'balanced',
  });

  factory FlightSearchRequest.fromJson(Map<String, dynamic> json) =>
      _$FlightSearchRequestFromJson(json);
  Map<String, dynamic> toJson() => _$FlightSearchRequestToJson(this);
}
