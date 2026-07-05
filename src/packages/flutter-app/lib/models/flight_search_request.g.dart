// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flight_search_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FlightSearchRequest _$FlightSearchRequestFromJson(Map<String, dynamic> json) =>
    FlightSearchRequest(
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      departDate: json['depart_date'] as String,
      returnDate: json['return_date'] as String?,
      adults: (json['adults'] as num?)?.toInt() ?? 1,
      childAges: (json['child_ages'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList(),
      cabinClass: json['cabin_class'] as String?,
      optimizeFor: json['optimize_for'] as String? ?? 'balanced',
    );

Map<String, dynamic> _$FlightSearchRequestToJson(FlightSearchRequest instance) {
  final val = <String, dynamic>{
    'origin': instance.origin,
    'destination': instance.destination,
    'depart_date': instance.departDate,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('return_date', instance.returnDate);
  val['adults'] = instance.adults;
  writeNotNull('child_ages', instance.childAges);
  writeNotNull('cabin_class', instance.cabinClass);
  val['optimize_for'] = instance.optimizeFor;
  return val;
}
