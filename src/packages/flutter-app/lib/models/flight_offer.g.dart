// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flight_offer.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FlightOffer _$FlightOfferFromJson(Map<String, dynamic> json) => FlightOffer(
      id: json['id'] as String,
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      stops: (json['stops'] as num).toInt(),
      durationMinutes: (json['duration_minutes'] as num).toInt(),
      airlines: (json['airlines'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      airlineCode: json['airline_code'] as String?,
      airlineLogoUrl: json['airline_logo_url'] as String?,
      departTime: json['depart_time'] as String,
      arriveTime: json['arrive_time'] as String,
      segments: (json['segments'] as List<dynamic>?)
              ?.map((e) => FlightLeg.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      bookingUrl: json['booking_url'] as String?,
      returnSegments: (json['return_segments'] as List<dynamic>?)
              ?.map((e) => FlightLeg.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      returnDurationMinutes:
          (json['return_duration_minutes'] as num?)?.toInt() ?? 0,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      priceScore: (json['price_score'] as num?)?.toDouble() ?? 0,
      durationScore: (json['duration_score'] as num?)?.toDouble() ?? 0,
      stopsScore: (json['stops_score'] as num?)?.toDouble() ?? 0,
    );

Map<String, dynamic> _$FlightOfferToJson(FlightOffer instance) =>
    <String, dynamic>{
      'id': instance.id,
      'price': instance.price,
      'currency': instance.currency,
      'stops': instance.stops,
      'duration_minutes': instance.durationMinutes,
      'airlines': instance.airlines,
      'airline_code': instance.airlineCode,
      'airline_logo_url': instance.airlineLogoUrl,
      'depart_time': instance.departTime,
      'arrive_time': instance.arriveTime,
      'segments': instance.segments.map((e) => e.toJson()).toList(),
      'booking_url': instance.bookingUrl,
      'return_segments':
          instance.returnSegments.map((e) => e.toJson()).toList(),
      'return_duration_minutes': instance.returnDurationMinutes,
      'score': instance.score,
      'price_score': instance.priceScore,
      'duration_score': instance.durationScore,
      'stops_score': instance.stopsScore,
    };
