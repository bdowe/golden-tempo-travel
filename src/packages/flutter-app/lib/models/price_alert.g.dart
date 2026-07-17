// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_alert.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceAlert _$PriceAlertFromJson(Map<String, dynamic> json) => PriceAlert(
      id: json['id'] as String,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      departDate: json['depart_date'] as String,
      returnDate: json['return_date'] as String?,
      cabinClass: json['cabin_class'] as String? ?? 'economy',
      adults: (json['adults'] as num?)?.toInt() ?? 1,
      targetPrice: (json['target_price'] as num?)?.toDouble(),
      flexDays: (json['flex_days'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String?,
      baselinePrice: (json['baseline_price'] as num?)?.toDouble(),
      lastCheckedPrice: (json['last_checked_price'] as num?)?.toDouble(),
      lastCheckedAt: json['last_checked_at'] as String?,
      lastNotifiedPrice: (json['last_notified_price'] as num?)?.toDouble(),
      lastNotifiedAt: json['last_notified_at'] as String?,
      status: json['status'] as String? ?? 'active',
      tripId: json['trip_id'] as String?,
      createdAt: json['created_at'] as String? ?? '',
    );

Map<String, dynamic> _$PriceAlertToJson(PriceAlert instance) =>
    <String, dynamic>{
      'id': instance.id,
      'origin': instance.origin,
      'destination': instance.destination,
      'depart_date': instance.departDate,
      'return_date': instance.returnDate,
      'cabin_class': instance.cabinClass,
      'adults': instance.adults,
      'target_price': instance.targetPrice,
      'flex_days': instance.flexDays,
      'currency': instance.currency,
      'baseline_price': instance.baselinePrice,
      'last_checked_price': instance.lastCheckedPrice,
      'last_checked_at': instance.lastCheckedAt,
      'last_notified_price': instance.lastNotifiedPrice,
      'last_notified_at': instance.lastNotifiedAt,
      'status': instance.status,
      'trip_id': instance.tripId,
      'created_at': instance.createdAt,
    };
