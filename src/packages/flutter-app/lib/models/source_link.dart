import 'package:json_annotation/json_annotation.dart';

part 'source_link.g.dart';

/// A labeled deep link to an external discovery/booking source, matching the Go
/// API's GreekEventLink (and reusable for any provider-link list). Used where
/// there's no structured data to show — e.g. Greek events via more.com /
/// visitgreece.gr / Athens-Epidaurus.
@JsonSerializable()
class SourceLink {
  @JsonKey(defaultValue: '')
  final String provider;
  @JsonKey(defaultValue: '')
  final String url;
  @JsonKey(defaultValue: '')
  final String label;

  const SourceLink({this.provider = '', this.url = '', this.label = ''});

  factory SourceLink.fromJson(Map<String, dynamic> json) =>
      _$SourceLinkFromJson(json);
  Map<String, dynamic> toJson() => _$SourceLinkToJson(this);
}
