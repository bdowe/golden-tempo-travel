import 'package:flutter_test/flutter_test.dart';
import 'package:travel_route_planner/utils/money_format.dart';

void main() {
  group('formatMoney', () {
    test('known codes render with their symbol, no space', () {
      expect(formatMoney(412, 'USD'), r'$412');
      expect(formatMoney(412, 'EUR'), '€412');
      expect(formatMoney(412, 'GBP'), '£412');
      expect(formatMoney(412, 'JPY'), '¥412');
    });

    test('disambiguating dollar variants keep their prefix', () {
      expect(formatMoney(412, 'CAD'), r'C$412');
      expect(formatMoney(412, 'AUD'), r'A$412');
      expect(formatMoney(412, 'NZD'), r'NZ$412');
    });

    test('case and surrounding whitespace are normalized', () {
      expect(formatMoney(50, ' usd '), r'$50');
      expect(formatMoney(50, 'eur'), '€50');
    });

    test('unknown code falls back to a visible code prefix', () {
      expect(formatMoney(412, 'CHF'), 'CHF 412');
      expect(formatMoney(412, 'ZZZ'), 'ZZZ 412');
    });

    test('empty code degrades to the bare number', () {
      expect(formatMoney(412, ''), '412');
      expect(formatMoney(412, '   '), '412');
    });

    test('amounts round to whole units', () {
      expect(formatMoney(412.4, 'USD'), r'$412');
      expect(formatMoney(412.6, 'USD'), r'$413');
      expect(formatMoney(412.6, 'CHF'), 'CHF 413');
    });

    test('zero renders cleanly', () {
      expect(formatMoney(0, 'EUR'), '€0');
      expect(formatMoney(0, 'CAD'), r'C$0');
      expect(formatMoney(0, 'ZZZ'), 'ZZZ 0');
    });

    test('negative amounts keep a leading minus', () {
      expect(formatMoney(-5, 'USD'), r'-$5');
      expect(formatMoney(-5, 'EUR'), '-€5');
      expect(formatMoney(-5, 'CHF'), '-CHF 5');
      expect(formatMoney(-5, ''), '-5');
    });
  });
}
