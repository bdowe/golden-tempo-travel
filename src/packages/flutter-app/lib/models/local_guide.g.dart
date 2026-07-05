// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_guide.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalGuide _$LocalGuideFromJson(Map<String, dynamic> json) => LocalGuide(
      id: json['id'] as String,
      title: json['title'] as String,
      city: json['city'] as String? ?? '',
      neighborhood: json['neighborhood'] as String? ?? '',
      body: json['body'] as String? ?? '',
      heroImageUrl: json['hero_image_url'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      sourcePhotoUrl: json['source_photo_url'] as String? ?? '',
    );

Map<String, dynamic> _$LocalGuideToJson(LocalGuide instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'city': instance.city,
      'neighborhood': instance.neighborhood,
      'body': instance.body,
      'hero_image_url': instance.heroImageUrl,
      'source_name': instance.sourceName,
      'source_photo_url': instance.sourcePhotoUrl,
    };
