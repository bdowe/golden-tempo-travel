// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AlertEvent _$AlertEventFromJson(Map<String, dynamic> json) => AlertEvent(
      id: json['id'] as String,
      alertId: json['alert_id'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      previousPrice: (json['previous_price'] as num?)?.toDouble(),
      occurredAt: json['occurred_at'] as String,
      readAt: json['read_at'] as String?,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      departDate: json['depart_date'] as String,
      returnDate: json['return_date'] as String?,
      targetPrice: (json['target_price'] as num?)?.toDouble(),
      alertStatus: json['alert_status'] as String,
    );

Map<String, dynamic> _$AlertEventToJson(AlertEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'alert_id': instance.alertId,
      'price': instance.price,
      'currency': instance.currency,
      'previous_price': instance.previousPrice,
      'occurred_at': instance.occurredAt,
      'read_at': instance.readAt,
      'origin': instance.origin,
      'destination': instance.destination,
      'depart_date': instance.departDate,
      'return_date': instance.returnDate,
      'target_price': instance.targetPrice,
      'alert_status': instance.alertStatus,
    };
