import '../models/accommodation.dart';
import '../models/trip_segment.dart';

/// Builders for the per-event "Add to calendar" affordance.
///
/// Google Calendar takes a prefilled calendar.google.com link built entirely
/// client-side (no server round-trip, no OAuth); Apple Calendar goes through
/// the token-gated per-event .ics endpoint instead (see exportEventIcsUrl in
/// share_link.dart). The date-range resolvers mirror the Go export semantics
/// (calendar_handler.go): everything is all-day with an EXCLUSIVE end, and a
/// null range means "undated — hide the affordance".

/// Prefilled Google Calendar event link (all-day; [endExclusive] follows the
/// same end-exclusive convention as the .ics export).
String googleCalendarUrl({
  required String title,
  required DateTime start,
  required DateTime endExclusive,
  String? location,
  String? details,
}) {
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_ymd(start)}/${_ymd(endExclusive)}',
    if (location != null && location.trim().isNotEmpty) 'location': location,
    if (details != null && details.trim().isNotEmpty) 'details': details,
  }).toString();
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// A stay spans check-in through check-out (one night when check-out is
/// missing or not after check-in). Null when check-in is missing/unparseable.
({DateTime start, DateTime endExclusive})? stayCalendarRange(Accommodation a) {
  final start = _parseDate(a.checkIn);
  if (start == null) return null;
  final checkOut = _parseDate(a.checkOut);
  final end = (checkOut != null && checkOut.isAfter(start))
      ? checkOut
      : start.add(const Duration(days: 1));
  return (start: start, endExclusive: end);
}

/// A segment spans departure day through arrival day inclusive (a single day
/// when arrival is missing). Null when the departure date is missing.
({DateTime start, DateTime endExclusive})? segmentCalendarRange(TripSegment s) {
  final start = _parseDate(s.departDate);
  if (start == null) return null;
  final arrive = _parseDate(s.arriveDate);
  final end = (arrive != null && arrive.isAfter(start))
      ? arrive.add(const Duration(days: 1))
      : start.add(const Duration(days: 1));
  return (start: start, endExclusive: end);
}

/// An itinerary item occupies the single trip day it's assigned to:
/// trip.start_date + (day - 1). Null without a trip start date or a day.
({DateTime start, DateTime endExclusive})? itemCalendarRange(
    String? tripStartDate, int? day) {
  final tripStart = _parseDate(tripStartDate);
  if (tripStart == null || day == null || day < 1) return null;
  final start = tripStart.add(Duration(days: day - 1));
  return (start: start, endExclusive: start.add(const Duration(days: 1)));
}

/// Parses a YYYY-MM-DD date to UTC midnight. UTC keeps the day arithmetic
/// above exact — adding Duration(days: 1) to a LOCAL DateTime shifts by an
/// hour across DST boundaries (see the Today-mode calendar-math lesson).
DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  final t = DateTime.tryParse(s);
  if (t == null) return null;
  return DateTime.utc(t.year, t.month, t.day);
}
