import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/weather.dart';
import '../services/weather_api_service.dart';
import 'api_client_provider.dart';

final weatherApiServiceProvider = Provider<WeatherApiService>((ref) {
  return WeatherApiService(ref.watch(apiClientProvider));
});

/// Identifies one weather lookup: a city and its date window. Used as the
/// family key so each city group in a trip caches its own report — one API
/// call per city per trip view.
class WeatherQuery {
  final String city;
  final String startDate; // YYYY-MM-DD
  final String endDate; // YYYY-MM-DD

  const WeatherQuery({
    required this.city,
    required this.startDate,
    required this.endDate,
  });

  @override
  bool operator ==(Object other) =>
      other is WeatherQuery &&
      other.city == city &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(city, startDate, endDate);
}

/// Trip weather for a city + date window. Best-effort: any failure resolves to
/// an empty report so weather never surfaces an error state that could block or
/// clutter the itinerary — the UI simply renders no chip.
final weatherByCityProvider =
    FutureProvider.family<WeatherReport, WeatherQuery>((ref, query) async {
  if (query.city.trim().isEmpty || query.startDate.isEmpty) {
    return const WeatherReport();
  }
  final service = ref.watch(weatherApiServiceProvider);
  try {
    return await service.getTripWeather(
      query.city.trim(),
      query.startDate,
      endDate: query.endDate,
    );
  } catch (_) {
    return const WeatherReport();
  }
});
