// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppNotification _$AppNotificationFromJson(Map<String, dynamic> json) =>
    AppNotification(
      id: json['id'] as String,
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>? ?? {},
      tripId: json['trip_id'] as String?,
      readAt: json['read_at'] as String?,
      createdAt: json['created_at'] as String,
    );

Map<String, dynamic> _$AppNotificationToJson(AppNotification instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'payload': instance.payload,
      'trip_id': instance.tripId,
      'read_at': instance.readAt,
      'created_at': instance.createdAt,
    };
