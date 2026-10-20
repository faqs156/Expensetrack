/// Local-calendar date helpers — avoids timezone drift for day/month buckets.
class DateKeys {
  DateKeys._();

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  static DateTime endOfMonth(DateTime d) {
    final next = (d.month == 12)
        ? DateTime(d.year + 1, 1, 1)
        : DateTime(d.year, d.month + 1, 1);
    return next.subtract(const Duration(milliseconds: 1));
  }

  static DateTime previousMonth(DateTime d) {
    final y = d.month == 1 ? d.year - 1 : d.year;
    final m = d.month == 1 ? 12 : d.month - 1;
    return DateTime(y, m, 1);
  }

  static DateTime nextMonth(DateTime d) {
    final y = d.month == 12 ? d.year + 1 : d.year;
    final m = d.month == 12 ? 1 : d.month + 1;
    return DateTime(y, m, 1);
  }

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static bool isCurrentMonth(DateTime d) {
    final now = DateTime.now();
    return isSameMonth(d, now);
  }

  static String monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
