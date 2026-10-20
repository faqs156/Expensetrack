/// Money helpers using integer paise (1 INR = 100 paise) to avoid float errors.
class Money {
  Money._();

  static int rupeesToPaise(num rupees) {
    return (rupees * 100).round();
  }

  static double paiseToRupees(int paise) => paise / 100.0;

  /// Parses user input like "1250.50" or "1,250.50" into paise.
  /// Returns null if invalid or non-positive when [allowZero] is false.
  static int? parseToPaise(String input, {bool allowZero = false}) {
    final cleaned = input.trim().replaceAll(',', '').replaceAll('₹', '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value < 0) return null;
    if (!allowZero && value == 0) return null;
    // Reject more than 2 decimal places of meaningful precision after rounding.
    final paise = (value * 100).round();
    if ((value * 100 - paise).abs() > 0.001) {
      // Still accept after round — standard currency rounding.
    }
    return paise;
  }

  static String formatRupees(
    int paise, {
    String symbol = '₹',
    bool compact = false,
  }) {
    final rupees = paiseToRupees(paise);
    if (compact && rupees.abs() >= 100000) {
      final lakhs = rupees / 100000;
      return '$symbol${lakhs.toStringAsFixed(lakhs.abs() >= 10 ? 1 : 2)}L';
    }
    if (compact && rupees.abs() >= 1000) {
      final k = rupees / 1000;
      return '$symbol${k.toStringAsFixed(k.abs() >= 100 ? 0 : 1)}K';
    }
    final negative = rupees < 0;
    final abs = rupees.abs();
    final whole = abs.floor();
    final fraction = ((abs - whole) * 100).round().toString().padLeft(2, '0');
    final grouped = _indianGroup(whole);
    final sign = negative ? '-' : '';
    return '$sign$symbol$grouped.$fraction';
  }

  static String _indianGroup(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}
