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
      fix: json['fix'] == null
          ? null
          : FindingFix.fromJson(json['fix'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TripFindingToJson(TripFinding instance) =>
    <String, dynamic>{
      'severity': instance.severity,
      'category': instance.category,
      'message': instance.message,
      'trip_id': instance.tripId,
      'day': instance.day,
      'item_id': instance.itemId,
      'fix': instance.fix,
    };

FindingFix _$FindingFixFromJson(Map<String, dynamic> json) => FindingFix(
      action: json['action'] as String,
      label: json['label'] as String,
      itemId: json['item_id'] as String?,
      entityType: json['entity_type'] as String?,
      targetDay: (json['target_day'] as num?)?.toInt(),
      city: json['city'] as String?,
      origin: json['origin'] as String?,
      destination: json['destination'] as String?,
      checkIn: json['check_in'] as String?,
      checkOut: json['check_out'] as String?,
      date: json['date'] as String?,
      mode: json['mode'] as String?,
      packingItem: json['packing_item'] as String?,
      packingCategory: json['packing_category'] as String?,
    );

Map<String, dynamic> _$FindingFixToJson(FindingFix instance) =>
    <String, dynamic>{
      'action': instance.action,
      'label': instance.label,
      'item_id': instance.itemId,
      'entity_type': instance.entityType,
      'target_day': instance.targetDay,
      'city': instance.city,
      'origin': instance.origin,
      'destination': instance.destination,
      'check_in': instance.checkIn,
      'check_out': instance.checkOut,
      'date': instance.date,
      'mode': instance.mode,
      'packing_item': instance.packingItem,
      'packing_category': instance.packingCategory,
    };
