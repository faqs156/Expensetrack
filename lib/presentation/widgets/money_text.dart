import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';

class MoneyText extends StatelessWidget {
  const MoneyText(
    this.paise, {
    super.key,
    this.symbol = '₹',
    this.style,
    this.signed = false,
    this.isIncome,
    this.compact = false,
  });

  final int paise;
  final String symbol;
  final TextStyle? style;
  final bool signed;
  final bool? isIncome;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final prefix = signed
        ? (isIncome == true ? '+' : (isIncome == false ? '−' : ''))
        : '';
    final color = isIncome == true
        ? AppColors.income
        : isIncome == false
        ? AppColors.expense
        : null;
    return Text(
      '$prefix${Money.formatRupees(paise.abs(), symbol: symbol, compact: compact)}',
      style: (style ?? Theme.of(context).textTheme.titleMedium)?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
