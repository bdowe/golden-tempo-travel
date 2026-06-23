import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/event.dart';
import '../models/source_link.dart';
import '../services/events_api_service.dart';
import 'api_client_provider.dart';

final eventsApiServiceProvider = Provider<EventsApiService>((ref) {
  return EventsApiService(ref.watch(apiClientProvider));
});

/// Identifies one events lookup: a city and its date window. Used as the
/// family key so each city group in a trip caches its own results.
class EventsQuery {
  final String city;
  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD
  final String? category;

  const EventsQuery({
    required this.city,
    required this.startDate,
    required this.endDate,
    this.category,
  });

  @override
  bool operator ==(Object other) =>
      other is EventsQuery &&
      other.city == city &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.category == category;

  @override
  int get hashCode => Object.hash(city, startDate, endDate, category);
}

/// Live events lookup for a city + date window. Returns [] for incomplete
/// queries so callers can render an empty state without special-casing.
final eventsByCityProvider =
    FutureProvider.family<List<Event>, EventsQuery>((ref, query) async {
  if (query.city.trim().isEmpty ||
      query.startDate.isEmpty ||
      query.endDate.isEmpty) {
    return [];
  }
  final service = ref.watch(eventsApiServiceProvider);
  return service.searchEvents(
    query.city.trim(),
    query.startDate,
    query.endDate,
    category: query.category,
  );
});

/// Curated Greek event-discovery links for a city + date window (empty for
/// non-Greek cities). Used as the trip-detail fallback when [eventsByCityProvider]
/// returns nothing for a Greek city.
final greeceEventLinksProvider =
    FutureProvider.family<List<SourceLink>, EventsQuery>((ref, query) async {
  if (query.city.trim().isEmpty) return [];
  final service = ref.watch(eventsApiServiceProvider);
  return service.greeceEventLinks(
    query.city.trim(),
    query.startDate,
    query.endDate,
  );
});
