// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_segment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TripSegment _$TripSegmentFromJson(Map<String, dynamic> json) => TripSegment(
      id: json['id'] as String,
      mode: json['mode'] as String,
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
      departDate: json['depart_date'] as String?,
      arriveDate: json['arrive_date'] as String?,
      provider: json['provider'] as String?,
      url: json['url'] as String?,
      priceNote: json['price_note'] as String?,
      notes: json['notes'] as String?,
      booked: json['booked'] as bool? ?? false,
      auto: json['auto'] as bool? ?? false,
      autoKey: json['auto_key'] as String?,
    );

Map<String, dynamic> _$TripSegmentToJson(TripSegment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'mode': instance.mode,
      'origin': instance.origin,
      'destination': instance.destination,
      'depart_date': instance.departDate,
      'arrive_date': instance.arriveDate,
      'provider': instance.provider,
      'url': instance.url,
      'price_note': instance.priceNote,
      'notes': instance.notes,
      'booked': instance.booked,
      'auto': instance.auto,
      'auto_key': instance.autoKey,
    };
