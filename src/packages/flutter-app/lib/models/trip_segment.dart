import 'package:json_annotation/json_annotation.dart';

part 'trip_segment.g.dart';

@JsonSerializable()
class TripSegment {
  final String id;
  final String mode; // flight | train | bus | car | ferry | other
  final String? origin;
  final String? destination;
  @JsonKey(name: 'depart_date')
  final String? departDate;
  @JsonKey(name: 'arrive_date')
  final String? arriveDate;
  final String? provider;
  final String? url;
  @JsonKey(name: 'price_note')
  final String? priceNote;
  final String? notes;

  /// The "Booked" checkbox in the bookings hub. defaultValue guards cached
  /// trip JSON written before the field existed.
  @JsonKey(defaultValue: false)
  final bool booked;

  /// True for itinerary-derived "Suggested" drafts owned by the booking-drafts
  /// sync; false for user-confirmed rows.
  final bool auto;
  @JsonKey(name: 'auto_key')
  final String? autoKey;

  const TripSegment({
    required this.id,
    required this.mode,
    this.origin,
    this.destination,
    this.departDate,
    this.arriveDate,
    this.provider,
    this.url,
    this.priceNote,
    this.notes,
    this.booked = false,
    this.auto = false,
    this.autoKey,
  });

  TripSegment copyWith({bool? booked}) => TripSegment(
        id: id,
        mode: mode,
        origin: origin,
        destination: destination,
        departDate: departDate,
        arriveDate: arriveDate,
        provider: provider,
        url: url,
        priceNote: priceNote,
        notes: notes,
        booked: booked ?? this.booked,
        auto: auto,
        autoKey: autoKey,
      );

  factory TripSegment.fromJson(Map<String, dynamic> json) =>
      _$TripSegmentFromJson(json);
  Map<String, dynamic> toJson() => _$TripSegmentToJson(this);
}
