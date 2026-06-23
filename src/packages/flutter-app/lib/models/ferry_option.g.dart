// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ferry_option.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FerryOption _$FerryOptionFromJson(Map<String, dynamic> json) => FerryOption(
      operator: json['operator'] as String? ?? '',
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      date: json['date'] as String? ?? '',
      departTime: json['depart_time'] as String? ?? '',
      arriveTime: json['arrive_time'] as String? ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? '',
      bookingUrl: json['booking_url'] as String? ?? '',
    );

Map<String, dynamic> _$FerryOptionToJson(FerryOption instance) =>
    <String, dynamic>{
      'operator': instance.operator,
      'from': instance.from,
      'to': instance.to,
      'date': instance.date,
      'depart_time': instance.departTime,
      'arrive_time': instance.arriveTime,
      'duration_minutes': instance.durationMinutes,
      'price': instance.price,
      'currency': instance.currency,
      'booking_url': instance.bookingUrl,
    };
