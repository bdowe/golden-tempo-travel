// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Trip _$TripFromJson(Map<String, dynamic> json) => Trip(
      id: json['id'] as String,
      title: json['title'] as String,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      status: json['status'] as String,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      items: (json['items'] as List<dynamic>?)
          ?.map((e) => ItineraryItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      accommodations: (json['accommodations'] as List<dynamic>?)
          ?.map((e) => Accommodation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TripToJson(Trip instance) => <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'start_date': instance.startDate,
      'end_date': instance.endDate,
      'status': instance.status,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
      'items': instance.items?.map((e) => e.toJson()).toList(),
      'accommodations':
          instance.accommodations?.map((e) => e.toJson()).toList(),
    };
