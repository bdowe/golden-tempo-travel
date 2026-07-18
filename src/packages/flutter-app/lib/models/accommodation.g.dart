// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accommodation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Accommodation _$AccommodationFromJson(Map<String, dynamic> json) =>
    Accommodation(
      id: json['id'] as String,
      name: json['name'] as String,
      provider: json['provider'] as String?,
      url: json['url'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      priceNote: json['price_note'] as String?,
      auto: json['auto'] as bool? ?? false,
      autoKey: json['auto_key'] as String?,
    );

Map<String, dynamic> _$AccommodationToJson(Accommodation instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'provider': instance.provider,
      'url': instance.url,
      'address': instance.address,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'check_in': instance.checkIn,
      'check_out': instance.checkOut,
      'price_note': instance.priceNote,
      'auto': instance.auto,
      'auto_key': instance.autoKey,
    };
