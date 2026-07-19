// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_finding.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TripFinding _$TripFindingFromJson(Map<String, dynamic> json) => TripFinding(
      severity: json['severity'] as String,
      category: json['category'] as String,
      message: json['message'] as String,
      tripId: json['trip_id'] as String,
      day: (json['day'] as num?)?.toInt(),
      itemId: json['item_id'] as String?,
    );

Map<String, dynamic> _$TripFindingToJson(TripFinding instance) =>
    <String, dynamic>{
      'severity': instance.severity,
      'category': instance.category,
      'message': instance.message,
      'trip_id': instance.tripId,
      'day': instance.day,
      'item_id': instance.itemId,
    };
