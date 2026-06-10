// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'traveler_preferences.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TravelerPreferences _$TravelerPreferencesFromJson(Map<String, dynamic> json) =>
    TravelerPreferences(
      budget: json['budget'] as String?,
      pace: json['pace'] as String?,
      interests: (json['interests'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      homeAirport: json['home_airport'] as String?,
    );

Map<String, dynamic> _$TravelerPreferencesToJson(
        TravelerPreferences instance) =>
    <String, dynamic>{
      'budget': instance.budget,
      'pace': instance.pace,
      'interests': instance.interests,
      'home_airport': instance.homeAirport,
    };
