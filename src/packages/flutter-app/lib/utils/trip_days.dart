// Shared trip-day math (specs/today-mode) so the trip detail screen, the
// shared trip view, and the add-to-trip sheet all agree on what "Day N" means.
//
// Pure and string-based like trip_format.dart: callers pass the raw ISO
// date-only strings (YYYY-MM-DD) straight off the models — no model imports.
// Dart parses date-only strings as **local** midnight, so all day math here is
// in the device's local calendar; "today" is wherever the device is.

/// The 1-based trip day that [when]'s **device-local calendar date** falls on,
/// or null when [startDate] is missing/unparseable or the date lands outside
/// the trip (before day 1, or past [endDate] when that parses).
///
/// [when]'s time of day is ignored (truncated to the local date), so passing
/// `DateTime.now()` answers "which trip day is today?".
int? tripDayOn(String? startDate, String? endDate, DateTime when) {
  final start = DateTime.tryParse(startDate ?? '');
  if (start == null) return null;
  final date = DateTime(when.year, when.month, when.day);
  final day = date.difference(start).inDays + 1;
  if (day < 1) return null;
  final end = DateTime.tryParse(endDate ?? '');
  if (end != null && day > end.difference(start).inDays + 1) return null;
  return day;
}

/// How many days a trip spans for day chips / pickers: the later of the
/// highest tagged day in [itemDays] and the [startDate]–[endDate] span (so an
/// empty dated trip still offers its real days, and an item tagged beyond the
/// span still gets a chip). 0 when the trip has neither dates nor tagged items.
int dayCount(String? startDate, String? endDate, Iterable<int?> itemDays) {
  var max = 0;
  for (final d in itemDays) {
    if (d != null && d > max) max = d;
  }
  final start = DateTime.tryParse(startDate ?? '');
  final end = DateTime.tryParse(endDate ?? '');
  if (start != null && end != null) {
    final span = end.difference(start).inDays + 1;
    if (span > max) max = span;
  }
  return max;
}

/// Whether a stay covers the night of [date] (device-local calendar date):
/// check-in <= date < check-out — **checkout-exclusive**, since nobody sleeps
/// there on checkout day. False when either date is missing or unparseable.
bool stayCoversDate(String? checkIn, String? checkOut, DateTime date) {
  final a = DateTime.tryParse(checkIn ?? '');
  final b = DateTime.tryParse(checkOut ?? '');
  if (a == null || b == null) return false;
  final d = DateTime(date.year, date.month, date.day);
  return !d.isBefore(DateTime(a.year, a.month, a.day)) &&
      d.isBefore(DateTime(b.year, b.month, b.day));
}
