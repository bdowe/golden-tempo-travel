import 'package:json_annotation/json_annotation.dart';

part 'local_guide.g.dart';

/// A narrative guide authored by a named local, returned by /local/guides.
/// Matches the Go API's ListPublishedGuidesByCityRow (list) shape.
@JsonSerializable()
class LocalGuide {
  final String id;
  final String title;
  @JsonKey(defaultValue: '')
  final String city;
  @JsonKey(defaultValue: '')
  final String neighborhood;
  @JsonKey(defaultValue: '')
  final String body;
  @JsonKey(name: 'hero_image_url', defaultValue: '')
  final String heroImageUrl;
  @JsonKey(name: 'source_name', defaultValue: '')
  final String sourceName;
  @JsonKey(name: 'source_photo_url', defaultValue: '')
  final String sourcePhotoUrl;

  const LocalGuide({
    required this.id,
    required this.title,
    this.city = '',
    this.neighborhood = '',
    this.body = '',
    this.heroImageUrl = '',
    this.sourceName = '',
    this.sourcePhotoUrl = '',
  });

  factory LocalGuide.fromJson(Map<String, dynamic> json) =>
      _$LocalGuideFromJson(json);
  Map<String, dynamic> toJson() => _$LocalGuideToJson(this);
}
