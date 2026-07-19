import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/models/flight_offer.dart';
import 'package:travel_route_planner/widgets/flight_offer_card.dart';

FlightOffer _offer(
  String id,
  double price, {
  String? baggageStatus,
  double? effectivePrice,
  String currency = 'USD',
}) =>
    FlightOffer(
      id: id,
      price: price,
      currency: currency,
      stops: 0,
      durationMinutes: 420,
      airlines: const ['TestAir'],
      departTime: '2026-09-01T18:00:00',
      arriveTime: '2026-09-02T07:00:00',
      segments: const [],
      baggageStatus: baggageStatus,
      effectivePrice: effectivePrice,
    );

void main() {
  group('savingsLabelFor', () {
    test('labels the saving between the best and next effective total', () {
      final offers = [
        _offer('a', 200, baggageStatus: 'included', effectivePrice: 200),
        _offer('b', 180, baggageStatus: 'paid', effectivePrice: 223),
        _offer('c', 190, baggageStatus: 'paid', effectivePrice: 250),
      ];
      expect(savingsLabelFor(offers, 'a'), 'Saves \$23 vs next option');
    });

    test('null on bare-fare searches (no baggage status)', () {
      final offers = [_offer('a', 200), _offer('b', 230)];
      expect(savingsLabelFor(offers, 'a'), isNull);
    });

    test('null when the best offer\'s bag fee is unknown', () {
      final offers = [
        _offer('a', 180, baggageStatus: 'unknown'),
        _offer('b', 200, baggageStatus: 'included', effectivePrice: 200),
      ];
      expect(savingsLabelFor(offers, 'a'), isNull);
    });

    test('skips unknown-fee and foreign-currency alternatives', () {
      final offers = [
        _offer('a', 200, baggageStatus: 'included', effectivePrice: 200),
        _offer('b', 150, baggageStatus: 'unknown'),
        _offer('c', 100, baggageStatus: 'paid', effectivePrice: 140,
            currency: 'EUR'),
        _offer('d', 210, baggageStatus: 'paid', effectivePrice: 260),
      ];
      expect(savingsLabelFor(offers, 'a'), 'Saves \$60 vs next option');
      expect(savingsLabelFor([offers[0], offers[1]], 'a'), isNull);
    });

    test('null when the best match is not the cheapest or saving rounds to 0',
        () {
      final dearerBest = [
        _offer('a', 260, baggageStatus: 'included', effectivePrice: 260),
        _offer('b', 180, baggageStatus: 'paid', effectivePrice: 223),
      ];
      expect(savingsLabelFor(dearerBest, 'a'), isNull);
      final nearTie = [
        _offer('a', 200, baggageStatus: 'included', effectivePrice: 200),
        _offer('b', 180, baggageStatus: 'paid', effectivePrice: 200.3),
      ];
      expect(savingsLabelFor(nearTie, 'a'), isNull);
    });

    test('null when the best offer id is absent', () {
      final offers = [
        _offer('a', 200, baggageStatus: 'included', effectivePrice: 200),
      ];
      expect(savingsLabelFor(offers, null), isNull);
      expect(savingsLabelFor(offers, 'zzz'), isNull);
    });
  });

  group('FlightOfferCard savings pill', () {
    testWidgets('renders the pill next to BEST MATCH when a label is passed',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FlightOfferCard(
            offer: _offer('a', 200,
                baggageStatus: 'included', effectivePrice: 200),
            isBest: true,
            savingsLabel: 'Saves \$23 vs next option',
          ),
        ),
      ));
      expect(find.text('BEST MATCH'), findsOneWidget);
      expect(find.text('Saves \$23 vs next option'), findsOneWidget);
    });

    testWidgets('renders no pill by default', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FlightOfferCard(
            offer: _offer('a', 200,
                baggageStatus: 'included', effectivePrice: 200),
            isBest: true,
          ),
        ),
      ));
      expect(find.text('BEST MATCH'), findsOneWidget);
      expect(find.textContaining('vs next option'), findsNothing);
    });
  });
}
