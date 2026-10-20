class MonthlyBudget {
  final String monthKey; // yyyy-MM
  final int overallPaise; // 0 = unset
  final Map<String, int> categoryPaise; // categoryId -> paise

  const MonthlyBudget({
    required this.monthKey,
    this.overallPaise = 0,
    this.categoryPaise = const {},
  });

  MonthlyBudget copyWith({
    String? monthKey,
    int? overallPaise,
    Map<String, int>? categoryPaise,
  }) {
    return MonthlyBudget(
      monthKey: monthKey ?? this.monthKey,
      overallPaise: overallPaise ?? this.overallPaise,
      categoryPaise: categoryPaise ?? this.categoryPaise,
    );
  }
}

class BudgetStatus {
  final int budgetPaise;
  final int spentPaise;

  const BudgetStatus({required this.budgetPaise, required this.spentPaise});

  bool get isSet => budgetPaise > 0;
  int get remainingPaise => budgetPaise - spentPaise;
  double get utilization =>
      !isSet || budgetPaise == 0 ? 0 : spentPaise / budgetPaise;

  /// 0 ok, 1 approaching (>=80%), 2 over
  int get warningLevel {
    if (!isSet) return 0;
    if (utilization >= 1) return 2;
    if (utilization >= 0.8) return 1;
    return 0;
  }
}
