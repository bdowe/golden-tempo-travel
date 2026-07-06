import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/airport.dart';
import 'package:travel_route_planner/models/flight_leg.dart';
import 'package:travel_route_planner/models/flight_offer.dart';
import 'package:travel_route_planner/models/flight_search_request.dart';
import 'package:travel_route_planner/models/flight_search_response.dart';
import 'package:travel_route_planner/models/price_alert.dart';
import 'package:travel_route_planner/models/user.dart';
import 'package:travel_route_planner/providers/alerts_provider.dart';
import 'package:travel_route_planner/providers/auth_provider.dart';
import 'package:travel_route_planner/providers/flights_provider.dart';
import 'package:travel_route_planner/screens/flight_search_screen.dart';
import 'package:travel_route_planner/services/alerts_api_service.dart';
import 'package:travel_route_planner/services/api_client.dart';
import 'package:travel_route_planner/services/flights_api_service.dart';
import 'package:travel_route_planner/widgets/create_alert_sheet.dart';
import 'package:travel_route_planner/widgets/flight_offer_card.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeAuthNotifier extends StateNotifier<AuthState>
    implements AuthNotifier {
  _FakeAuthNotifier(UserModel? user)
      : super(AuthState(user: user, initialized: true));

  @override
  Future<bool> login(String email, String password) async => false;

  @override
  Future<bool> register(String email, String password,
          {String? displayName}) async =>
      false;

  @override
  Future<void> completeOnboarding() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> signOutLocally() async {}

  @override
  void setUser(UserModel user) {}

  @override
  Future<void> adoptSession(String token, UserModel user) async {}
}

class _FakeAlertsApiService extends AlertsApiService {
  final List<Map<String, dynamic>> created = [];
  _FakeAlertsApiService() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<PriceAlert> create(Map<String, dynamic> body) async {
    created.add(body);
    return PriceAlert(
      id: 'a1',
      origin: body['origin'] as String,
      destination: body['destination'] as String,
      departDate: body['depart_date'] as String,
      returnDate: body['return_date'] as String?,
    );
  }
}

/// Captures every search request; answers with one offer that mirrors the
/// request's shape (round-trip offers carry return segments, like the API).
class _FakeFlightsApiService extends FlightsApiService {
  final List<FlightSearchRequest> requests = [];
  _FakeFlightsApiService() : super(ApiClient(baseUrl: 'http://test'));

  @override
  Future<FlightSearchResponse> searchFlights(FlightSearchRequest request) async {
    requests.add(request);
    final offer = request.returnDate == null ? _oneWayOffer() : _roundTripOffer();
    return FlightSearchResponse(
      offers: [offer],
      bestOfferId: offer.id,
      optimizeFor: request.optimizeFor,
      count: 1,
      status: 'success',
    );
  }

  @override
  Future<List<Airport>> searchAirports(String query) async => [];
}

UserModel _user() => UserModel(
      id: 'user-1',
      email: 'test@example.com',
      displayName: 'Test',
      createdAt: DateTime(2026, 1, 1),
    );

const _outboundLeg = FlightLeg(
  from: 'JFK',
  to: 'CDG',
  carrier: 'Air France',
  flightNumber: 'AF11',
  departTime: '2026-09-01T18:00:00',
  arriveTime: '2026-09-02T07:30:00',
);

const _returnLeg = FlightLeg(
  from: 'CDG',
  to: 'JFK',
  carrier: 'Air France',
  flightNumber: 'AF22',
  departTime: '2026-09-10T10:00:00',
  arriveTime: '2026-09-10T12:15:00',
);

FlightOffer _oneWayOffer() => const FlightOffer(
      id: 'off_ow',
      price: 420,
      currency: 'USD',
      stops: 0,
      durationMinutes: 450,
      airlines: ['Air France'],
      departTime: '2026-09-01T18:00:00',
      arriveTime: '2026-09-02T07:30:00',
      segments: [_outboundLeg],
      bookingUrl: 'https://example.com/book',
    );

FlightOffer _roundTripOffer() => const FlightOffer(
      id: 'off_rt',
      price: 842,
      currency: 'USD',
      stops: 0,
      durationMinutes: 450,
      airlines: ['Air France'],
      departTime: '2026-09-01T18:00:00',
      arriveTime: '2026-09-02T07:30:00',
      segments: [_outboundLeg],
      returnSegments: [_returnLeg],
      returnDurationMinutes: 495,
      bookingUrl: 'https://example.com/book',
    );

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  group('FlightSearchRequest JSON', () {
    test('omits return_date when null (one-way unchanged)', () {
      const req = FlightSearchRequest(
          origin: 'JFK', destination: 'CDG', departDate: '2026-09-01');
      expect(req.toJson().containsKey('return_date'), isFalse);
    });

    test('carries return_date when set', () {
      const req = FlightSearchRequest(
          origin: 'JFK',
          destination: 'CDG',
          departDate: '2026-09-01',
          returnDate: '2026-09-10');
      expect(req.toJson()['return_date'], '2026-09-10');
    });
  });

  group('FlightOffer model', () {
    test('parses return_segments from API JSON', () {
      final offer = FlightOffer.fromJson({
        'id': 'off_rt',
        'price': 842.4,
        'currency': 'USD',
        'stops': 0,
        'duration_minutes': 450,
        'airlines': ['Air France'],
        'depart_time': '2026-09-01T18:00:00',
        'arrive_time': '2026-09-02T07:30:00',
        'segments': [
          {
            'from': 'JFK',
            'to': 'CDG',
            'carrier': 'Air France',
            'flight_number': 'AF11',
            'depart_time': '2026-09-01T18:00:00',
            'arrive_time': '2026-09-02T07:30:00',
          }
        ],
        'return_segments': [
          {
            'from': 'CDG',
            'to': 'JFK',
            'carrier': 'Air France',
            'flight_number': 'AF22',
            'depart_time': '2026-09-10T10:00:00',
            'arrive_time': '2026-09-10T12:15:00',
          }
        ],
        'return_duration_minutes': 495,
        'score': 0,
        'price_score': 0,
        'duration_score': 0,
        'stops_score': 0,
      });
      expect(offer.isRoundTrip, isTrue);
      expect(offer.returnSegments.single.from, 'CDG');
      expect(offer.returnDurationLabel, '8h 15m');
      expect(offer.combinedStopsLabel, 'Nonstop');
    });

    test('one-way offer without return fields is unchanged', () {
      final offer = _oneWayOffer();
      expect(offer.isRoundTrip, isFalse);
      expect(offer.returnSegments, isEmpty);
      expect(offer.combinedStopsLabel, offer.stopsLabel);
    });

    test('combinedStopsLabel covers matching and differing directions', () {
      FlightOffer offer({required int stops, required int returnLegs}) =>
          FlightOffer(
            id: 'o',
            price: 1,
            currency: 'USD',
            stops: stops,
            durationMinutes: 60,
            airlines: const [],
            departTime: '',
            arriveTime: '',
            segments: List.filled(stops + 1, _outboundLeg),
            returnSegments: List.filled(returnLegs, _returnLeg),
            returnDurationMinutes: 60,
          );
      expect(offer(stops: 1, returnLegs: 2).combinedStopsLabel,
          '1 stop each way');
      expect(offer(stops: 0, returnLegs: 2).combinedStopsLabel,
          'Nonstop / 1 stop');
    });
  });

  group('FlightOfferCard', () {
    Future<void> pumpCard(WidgetTester tester, FlightOffer offer) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FlightOfferCard(offer: offer)),
      ));
    }

    testWidgets('round trip renders both slices and combined stats',
        (tester) async {
      await pumpCard(tester, _roundTripOffer());
      expect(
          find.textContaining('JFK 18:00', findRichText: true), findsOneWidget);
      expect(
          find.textContaining('CDG 10:00', findRichText: true), findsOneWidget);
      expect(find.text('7h 30m + 8h 15m'), findsOneWidget);
      expect(find.text('Nonstop'), findsOneWidget);
    });

    testWidgets('one way renders a single slice exactly as before',
        (tester) async {
      await pumpCard(tester, _oneWayOffer());
      expect(
          find.textContaining('JFK 18:00', findRichText: true), findsOneWidget);
      expect(
          find.textContaining('CDG 10:00', findRichText: true), findsNothing);
      expect(find.text('7h 30m'), findsOneWidget);
      expect(find.text('Nonstop'), findsOneWidget);
    });

    testWidgets('details sheet shows Outbound and Return sections',
        (tester) async {
      await pumpCard(tester, _roundTripOffer());
      await tester.tap(find.byType(FlightOfferCard));
      await tester.pumpAndSettle();
      expect(find.text('Outbound'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text('Round trip'), findsOneWidget);
      expect(find.text('JFK ⇄ CDG'), findsOneWidget);
    });

    testWidgets('details sheet for one way has no direction sections',
        (tester) async {
      await pumpCard(tester, _oneWayOffer());
      await tester.tap(find.byType(FlightOfferCard));
      await tester.pumpAndSettle();
      expect(find.text('Outbound'), findsNothing);
      expect(find.text('Return'), findsNothing);
      expect(find.text('JFK → CDG'), findsOneWidget);
    });
  });

  group('CreateAlertSheet', () {
    Future<_FakeAlertsApiService> openSheet(
        WidgetTester tester, CreateAlertSheet sheet) async {
      final service = _FakeAlertsApiService();
      await tester.pumpWidget(ProviderScope(
        overrides: [alertsApiServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => CreateAlertSheet.show(context, sheet),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return service;
    }

    testWidgets('round-trip search stores return_date on the alert',
        (tester) async {
      final service = await openSheet(
        tester,
        const CreateAlertSheet(
          origin: 'JFK',
          destination: 'CDG',
          departDate: '2026-09-01',
          returnDate: '2026-09-10',
        ),
      );
      // The summary shows what will be watched, including the return.
      expect(find.textContaining('2026-09-01 → 2026-09-10'), findsOneWidget);

      await tester.tap(find.text('Create alert'));
      await tester.pumpAndSettle();

      expect(service.created.single['return_date'], '2026-09-10');
    });

    testWidgets('one-way search omits return_date', (tester) async {
      final service = await openSheet(
        tester,
        const CreateAlertSheet(
          origin: 'JFK',
          destination: 'CDG',
          departDate: '2026-09-01',
        ),
      );
      await tester.tap(find.text('Create alert'));
      await tester.pumpAndSettle();

      expect(service.created.single.containsKey('return_date'), isFalse);
    });
  });

  group('FlightSearchScreen round trip', () {
    Future<(_FakeFlightsApiService, _FakeAlertsApiService)> pumpScreen(
        WidgetTester tester, String departDate) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final flights = _FakeFlightsApiService();
      final alerts = _FakeAlertsApiService();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          flightsApiServiceProvider.overrideWithValue(flights),
          alertsApiServiceProvider.overrideWithValue(alerts),
          authProvider.overrideWith((ref) => _FakeAuthNotifier(_user())),
        ],
        child: MaterialApp(
          home: FlightSearchScreen(
            prefillOrigin: 'JFK',
            prefillDestination: 'CDG',
            prefillDepartDate: departDate,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return (flights, alerts);
    }

    testWidgets(
        'return date threads through search request and Watch this route',
        (tester) async {
      final depart = DateTime.now().add(const Duration(days: 30));
      final (flights, alerts) = await pumpScreen(tester, _fmt(depart));

      // Prefill auto-search runs one-way: no return_date, current behavior.
      expect(flights.requests, hasLength(1));
      expect(flights.requests.first.returnDate, isNull);
      expect(find.text('Return (optional)'), findsOneWidget);

      // Pick a return date; the picker opens at departure + 7, accept it.
      await tester.tap(find.text('Return (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      final expectedReturn = _fmt(depart.add(const Duration(days: 7)));
      expect(find.text(expectedReturn), findsOneWidget);

      await tester.tap(find.text('Search Flights'));
      await tester.pumpAndSettle();
      expect(flights.requests, hasLength(2));
      expect(flights.requests.last.returnDate, expectedReturn);
      expect(flights.requests.last.origin, 'JFK');
      expect(flights.requests.last.destination, 'CDG');

      // Both slices render on the result card.
      expect(
          find.textContaining('CDG 10:00', findRichText: true), findsOneWidget);

      // "Watch this route" carries the searched return date into the alert.
      await tester
          .tap(find.textContaining('Watch this route'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('→ $expectedReturn'), findsOneWidget);
      await tester.tap(find.text('Create alert'));
      await tester.pumpAndSettle();
      expect(alerts.created.single['return_date'], expectedReturn);
      expect(alerts.created.single['depart_date'], _fmt(depart));
    });

    testWidgets('clear button removes the return date (back to one-way)',
        (tester) async {
      final depart = DateTime.now().add(const Duration(days: 30));
      final (flights, _) = await pumpScreen(tester, _fmt(depart));

      await tester.tap(find.text('Return (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Return (optional)'), findsNothing);

      await tester.tap(find.byTooltip('Clear return date'));
      await tester.pumpAndSettle();
      expect(find.text('Return (optional)'), findsOneWidget);

      await tester.tap(find.text('Search Flights'));
      await tester.pumpAndSettle();
      expect(flights.requests.last.returnDate, isNull);
    });

    testWidgets('moving departure past the return clears the return',
        (tester) async {
      final depart = DateTime.now().add(const Duration(days: 30));
      await pumpScreen(tester, _fmt(depart));

      // Set return = departure + 7.
      await tester.tap(find.text('Return (optional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Return (optional)'), findsNothing);

      // Move the departure into the next month (always past return).
      await tester.tap(find.text(_fmt(depart)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('28'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // The stale return is gone rather than silently invalid.
      expect(find.text('Return (optional)'), findsOneWidget);
    });
  });
}
