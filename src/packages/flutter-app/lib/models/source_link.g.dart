// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SourceLink _$SourceLinkFromJson(Map<String, dynamic> json) => SourceLink(
      provider: json['provider'] as String? ?? '',
      url: json['url'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );

Map<String, dynamic> _$SourceLinkToJson(SourceLink instance) =>
    <String, dynamic>{
      'provider': instance.provider,
      'url': instance.url,
      'label': instance.label,
    };
