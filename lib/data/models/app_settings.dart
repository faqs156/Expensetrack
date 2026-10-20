enum ThemePreference { system, light, dark }

class AppSettings {
  final ThemePreference theme;
  final String currencyCode;
  final String currencySymbol;
  final int defaultOverallBudgetPaise;

  const AppSettings({
    this.theme = ThemePreference.system,
    this.currencyCode = 'INR',
    this.currencySymbol = '₹',
    this.defaultOverallBudgetPaise = 0,
  });

  AppSettings copyWith({
    ThemePreference? theme,
    String? currencyCode,
    String? currencySymbol,
    int? defaultOverallBudgetPaise,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      defaultOverallBudgetPaise:
          defaultOverallBudgetPaise ?? this.defaultOverallBudgetPaise,
    );
  }
}
