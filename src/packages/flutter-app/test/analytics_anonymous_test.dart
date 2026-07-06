import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:travel_route_planner/services/analytics_api_service.dart';
import 'package:travel_route_planner/services/api_client.dart';

/// The anonymous top-of-funnel contract: whitelisted events POST without an
/// Authorization header when signed out instead of being dropped, and signed-in
/// events still carry the bearer token.
void main() {
  late List<http.Request> requests;
  late ApiClient apiClient;
  late AnalyticsApiService service;

  setUp(() {
    requests = [];
    apiClient = ApiClient(
      baseUrl: 'http://api.test/api/v1',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', 202);
      }),
    );
    service = AnalyticsApiService(apiClient);
  });

  test('signed-out booking click is sent anonymously (no Authorization)',
      () async {
    apiClient.authToken = null;
    await service.recordBookingLinkClicked(
      tripId: 'trip-1',
      provider: 'duffel',
      surface: 'flight_card',
    );

    expect(requests, hasLength(1));
    final req = requests.single;
    expect(req.url.path, '/api/v1/events');
    expect(req.headers.containsKey('Authorization'), isFalse,
        reason: 'anonymous events must not carry a credential');
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['event_type'], 'booking_link_clicked');
    expect((body['metadata'] as Map)['provider'], 'duffel');
  });

  test('signed-out landing view is sent anonymously', () async {
    apiClient.authToken = null;
    await service.recordLandingViewed();

    expect(requests, hasLength(1));
    final req = requests.single;
    expect(req.headers.containsKey('Authorization'), isFalse);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['event_type'], 'landing_viewed');
    expect(body.containsKey('trip_id'), isFalse);
  });

  test('signed-in booking click still carries the bearer token', () async {
    apiClient.authToken = 'session-token';
    await service.recordBookingLinkClicked(provider: 'duffel');

    expect(requests, hasLength(1));
    expect(requests.single.headers['Authorization'], 'Bearer session-token');
  });

  test('a transport failure is swallowed, never thrown', () async {
    final failing = AnalyticsApiService(ApiClient(
      baseUrl: 'http://api.test/api/v1',
      client: MockClient((_) async => throw Exception('network down')),
    ));
    await failing.recordLandingViewed(); // must not throw
    await failing.recordBookingLinkClicked(provider: 'duffel');
  });
}
