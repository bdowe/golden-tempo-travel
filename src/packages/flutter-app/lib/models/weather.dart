import 'package:json_annotation/json_annotation.dart';

part 'weather.g.dart';

/// One day of the trip weather, matching the Go API's WeatherDay. For a
/// forecast, [precipProbability] carries the chance of rain (%); the archive
/// ("historical") branch leaves it null and only reports observed rainfall.
@JsonSerializable()
class WeatherDay {
  final String date; // YYYY-MM-DD
  @JsonKey(name: 'temp_min_c', defaultValue: 0)
  final double tempMinC;
  @JsonKey(name: 'temp_max_c', defaultValue: 0)
  final double tempMaxC;
  @JsonKey(name: 'precip_mm', defaultValue: 0)
  final double precipMm;
  @JsonKey(name: 'precip_probability')
  final int? precipProbability;

  const WeatherDay({
    required this.date,
    this.tempMinC = 0,
    this.tempMaxC = 0,
    this.precipMm = 0,
    this.precipProbability,
  });

  /// Month-day key ("MM-DD") for matching a trip day to its weather. The
  /// historical branch returns last year's dates for the same month-day, so we
  /// match on month-day rather than the full date.
  String get monthDayKey => date.length >= 10 ? date.substring(5, 10) : date;

  factory WeatherDay.fromJson(Map<String, dynamic> json) =>
      _$WeatherDayFromJson(json);
  Map<String, dynamic> toJson() => _$WeatherDayToJson(this);
}

/// Trip weather report from /weather, matching the Go API's WeatherReport.
/// [kind] is "forecast" within the 16-day horizon, else "historical" (last
/// year's observations, surfaced as "typical").
@JsonSerializable()
class WeatherReport {
  @JsonKey(defaultValue: '')
  final String location;
  @JsonKey(defaultValue: '')
  final String kind;
  @JsonKey(defaultValue: <WeatherDay>[])
  final List<WeatherDay> days;

  const WeatherReport({
    this.location = '',
    this.kind = '',
    this.days = const [],
  });

  bool get isHistorical => kind == 'historical';

  /// The day matching [monthDay] ("MM-DD"), or null when the report has no
  /// entry for that date (undated day, out of the fetched window).
  ///
  /// Leap-day fallback: a historical report is keyed off last year's dates, and
  /// a Feb 29 trip day rolls to the prior (non-leap) year's Mar 1 server-side,
  /// so the archive holds no "02-29" and an exact match would leave that one day
  /// with no chip. When the exact key is absent we borrow the nearest adjacent
  /// calendar day's typical weather (02-29 -> 02-28, then 03-01). The fallback
  /// only fires when there's no exact entry, so ordinary days are unaffected.
  WeatherDay? dayFor(String monthDay) {
    for (final d in days) {
      if (d.monthDayKey == monthDay) return d;
    }
    for (final adjacent in _adjacentMonthDays(monthDay)) {
      for (final d in days) {
        if (d.monthDayKey == adjacent) return d;
      }
    }
    return null;
  }

  /// Previous- then next-calendar-day "MM-DD" keys for [monthDay], parsed in a
  /// leap year so "02-29" is valid. Empty when [monthDay] isn't a valid MM-DD.
  static List<String> _adjacentMonthDays(String monthDay) {
    if (monthDay.length != 5) return const [];
    final month = int.tryParse(monthDay.substring(0, 2));
    final day = int.tryParse(monthDay.substring(3, 5));
    if (month == null || day == null) return const [];
    final base = DateTime(2024, month, day); // leap year: 02-29 is valid
    String key(DateTime d) => '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return [
      key(base.subtract(const Duration(days: 1))),
      key(base.add(const Duration(days: 1))),
    ];
  }

  factory WeatherReport.fromJson(Map<String, dynamic> json) =>
      _$WeatherReportFromJson(json);
  Map<String, dynamic> toJson() => _$WeatherReportToJson(this);
}
