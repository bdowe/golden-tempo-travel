import 'dart:convert';
import '../models/weather.dart';
import 'api_client.dart';

/// Wraps the /weather endpoint (Open-Meteo-backed, keyless). Like events, the
/// endpoint is public, but we still send the bearer token when present to match
/// the other services.
class WeatherApiService {
  final ApiClient apiClient;

  WeatherApiService(this.apiClient);

  /// Trip weather for [city] between [startDate] and [endDate] (YYYY-MM-DD;
  /// [endDate] defaults to [startDate] server-side when empty). The endpoint is
  /// best-effort and returns an empty report on a geocode miss, so a normal
  /// "no weather" answer is a 200 with no days.
  Future<WeatherReport> getTripWeather(
    String city,
    String startDate, {
    String? endDate,
  }) async {
    final uri = Uri.parse('${apiClient.baseUrl}/weather').replace(
      queryParameters: {
        'city': city,
        'start_date': startDate,
        if (endDate != null && endDate.isNotEmpty) 'end_date': endDate,
      },
    );
    final res =
        await apiClient.httpClient.get(uri, headers: apiClient.jsonHeaders());
    if (res.statusCode == 200) {
      return WeatherReport.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to fetch weather: ${res.body}',
      endpoint: 'weather',
    );
  }
}
