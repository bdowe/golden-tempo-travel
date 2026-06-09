// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'itinerary_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ItineraryItem _$ItineraryItemFromJson(Map<String, dynamic> json) =>
    ItineraryItem(
      id: json['id'] as String,
      position: (json['position'] as num).toInt(),
      name: json['name'] as String,
      placeId: json['place_id'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      category: json['category'] as String?,
      timeOfDay: json['time_of_day'] as String?,
      city: json['city'] as String?,
      dayTripFrom: json['day_trip_from'] as String?,
    );

Map<String, dynamic> _$ItineraryItemToJson(ItineraryItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'position': instance.position,
      'name': instance.name,
      'place_id': instance.placeId,
      'address': instance.address,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'category': instance.category,
      'time_of_day': instance.timeOfDay,
      'city': instance.city,
      'day_trip_from': instance.dayTripFrom,
    };
