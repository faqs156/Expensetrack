import 'package:expense_track/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money', () {
    test('parses decimals to paise without float drift', () {
      expect(Money.parseToPaise('10.50'), 1050);
      expect(Money.parseToPaise('0.01'), 1);
      expect(Money.parseToPaise('1,250.75'), 125075);
      expect(Money.parseToPaise('₹100'), 10000);
    });

    test('rejects invalid and zero by default', () {
      expect(Money.parseToPaise(''), null);
      expect(Money.parseToPaise('abc'), null);
      expect(Money.parseToPaise('0'), null);
      expect(Money.parseToPaise('-5'), null);
      expect(Money.parseToPaise('0', allowZero: true), 0);
    });

    test('formats with Indian grouping', () {
      expect(Money.formatRupees(105000), '₹1,050.00'); // 105000 paise = ₹1,050
      expect(Money.formatRupees(10000000), '₹1,00,000.00'); // ₹1,00,000
    });

    test('rupees/paise round-trip', () {
      expect(Money.rupeesToPaise(99.99), 9999);
      expect(Money.paiseToRupees(9999), 99.99);
    });
  });
}
