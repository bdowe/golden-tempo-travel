// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WeatherDay _$WeatherDayFromJson(Map<String, dynamic> json) => WeatherDay(
      date: json['date'] as String,
      tempMinC: (json['temp_min_c'] as num?)?.toDouble() ?? 0,
      tempMaxC: (json['temp_max_c'] as num?)?.toDouble() ?? 0,
      precipMm: (json['precip_mm'] as num?)?.toDouble() ?? 0,
      precipProbability: (json['precip_probability'] as num?)?.toInt(),
    );

Map<String, dynamic> _$WeatherDayToJson(WeatherDay instance) =>
    <String, dynamic>{
      'date': instance.date,
      'temp_min_c': instance.tempMinC,
      'temp_max_c': instance.tempMaxC,
      'precip_mm': instance.precipMm,
      'precip_probability': instance.precipProbability,
    };

WeatherReport _$WeatherReportFromJson(Map<String, dynamic> json) =>
    WeatherReport(
      location: json['location'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      days: (json['days'] as List<dynamic>?)
              ?.map((e) => WeatherDay.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$WeatherReportToJson(WeatherReport instance) =>
    <String, dynamic>{
      'location': instance.location,
      'kind': instance.kind,
      'days': instance.days,
    };
