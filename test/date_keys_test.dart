import 'package:expense_track/core/date_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('month boundaries', () {
    final march = DateTime(2026, 3, 15);
    expect(DateKeys.startOfMonth(march), DateTime(2026, 3, 1));
    expect(DateKeys.endOfMonth(march).day, 31);
    expect(DateKeys.previousMonth(march), DateTime(2026, 2, 1));
    expect(DateKeys.nextMonth(march), DateTime(2026, 4, 1));
    expect(DateKeys.monthKey(march), '2026-03');
  });

  test('year wrap for previous/next month', () {
    expect(DateKeys.previousMonth(DateTime(2026, 1, 5)), DateTime(2025, 12, 1));
    expect(DateKeys.nextMonth(DateTime(2025, 12, 5)), DateTime(2026, 1, 1));
  });
}
