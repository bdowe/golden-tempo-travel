import 'package:json_annotation/json_annotation.dart';

part 'ferry_option.g.dart';

/// A ferry option returned by /ferries/search, matching the Go API's
/// FerryOption. In v1 (Ferryhopper deep-link mode) only [from], [to], [date],
/// and [bookingUrl] are populated; the structured fields fill once a real ferry
/// API is wired in.
@JsonSerializable()
class FerryOption {
  @JsonKey(defaultValue: '')
  final String operator;
  @JsonKey(defaultValue: '')
  final String from;
  @JsonKey(defaultValue: '')
  final String to;
  @JsonKey(defaultValue: '')
  final String date;
  @JsonKey(name: 'depart_time', defaultValue: '')
  final String departTime;
  @JsonKey(name: 'arrive_time', defaultValue: '')
  final String arriveTime;
  @JsonKey(name: 'duration_minutes', defaultValue: 0)
  final int durationMinutes;
  @JsonKey(defaultValue: 0)
  final double price;
  @JsonKey(defaultValue: '')
  final String currency;
  @JsonKey(name: 'booking_url', defaultValue: '')
  final String bookingUrl;

  const FerryOption({
    this.operator = '',
    this.from = '',
    this.to = '',
    this.date = '',
    this.departTime = '',
    this.arriveTime = '',
    this.durationMinutes = 0,
    this.price = 0,
    this.currency = '',
    this.bookingUrl = '',
  });

  /// "Santorini → Naxos" route label.
  String get routeLabel => '$from → $to';

  factory FerryOption.fromJson(Map<String, dynamic> json) =>
      _$FerryOptionFromJson(json);
  Map<String, dynamic> toJson() => _$FerryOptionToJson(this);
}
