import 'package:json_annotation/json_annotation.dart';

part 'accommodation.g.dart';

@JsonSerializable()
class Accommodation {
  final String id;
  final String name;
  final String? provider;
  final String? url;
  final String? address;
  final double? latitude;
  final double? longitude;
  @JsonKey(name: 'check_in')
  final String? checkIn;
  @JsonKey(name: 'check_out')
  final String? checkOut;
  @JsonKey(name: 'price_note')
  final String? priceNote;

  /// The "Booked" checkbox in the bookings hub. defaultValue guards cached
  /// trip JSON written before the field existed.
  @JsonKey(defaultValue: false)
  final bool booked;

  /// True for itinerary-derived "Suggested" drafts owned by the booking-drafts
  /// sync; false for user-confirmed rows.
  final bool auto;
  @JsonKey(name: 'auto_key')
  final String? autoKey;

  const Accommodation({
    required this.id,
    required this.name,
    this.provider,
    this.url,
    this.address,
    this.latitude,
    this.longitude,
    this.checkIn,
    this.checkOut,
    this.priceNote,
    this.booked = false,
    this.auto = false,
    this.autoKey,
  });

  Accommodation copyWith({bool? booked}) => Accommodation(
        id: id,
        name: name,
        provider: provider,
        url: url,
        address: address,
        latitude: latitude,
        longitude: longitude,
        checkIn: checkIn,
        checkOut: checkOut,
        priceNote: priceNote,
        booked: booked ?? this.booked,
        auto: auto,
        autoKey: autoKey,
      );

  factory Accommodation.fromJson(Map<String, dynamic> json) =>
      _$AccommodationFromJson(json);
  Map<String, dynamic> toJson() => _$AccommodationToJson(this);
}
