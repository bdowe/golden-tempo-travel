// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Event _$EventFromJson(Map<String, dynamic> json) => Event(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      venue: json['venue'] as String? ?? '',
      city: json['city'] as String? ?? '',
      startDate: json['start_date'] as String? ?? '',
      startTime: json['start_time'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      url: json['url'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
    );

Map<String, dynamic> _$EventToJson(Event instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'category': instance.category,
      'venue': instance.venue,
      'city': instance.city,
      'start_date': instance.startDate,
      'start_time': instance.startTime,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'url': instance.url,
      'image_url': instance.imageUrl,
    };
