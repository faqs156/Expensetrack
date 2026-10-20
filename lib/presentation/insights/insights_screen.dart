import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/date_keys.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../state/app_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/soft_card.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);
    final symbol = app.settings.currencySymbol;
    final hasData =
        app.monthTotals.expensePaise > 0 || app.monthTotals.incomePaise > 0;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insights',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => app.setSelectedMonth(
                        DateKeys.previousMonth(app.selectedMonth),
                      ),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        DateFormat('MMMM yyyy').format(app.selectedMonth),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: DateKeys.isCurrentMonth(app.selectedMonth)
                          ? null
                          : () => app.setSelectedMonth(
                              DateKeys.nextMonth(app.selectedMonth),
                            ),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!hasData)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.insights_outlined,
              title: 'Nothing to analyze',
              message: 'Add a few transactions to unlock spending trends and category breakdowns.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            sliver: SliverList.list(
              children: [
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Income vs expenses',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              label: 'Income',
                              paise: app.monthTotals.incomePaise,
                              symbol: symbol,
                              color: AppColors.income,
                            ),
                          ),
                          Expanded(
                            child: _Stat(
                              label: 'Expenses',
                              paise: app.monthTotals.expensePaise,
                              symbol: symbol,
                              color: AppColors.expense,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Net ${Money.formatRupees(app.monthTotals.netPaise, symbol: symbol)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: app.monthTotals.netPaise >= 0
                              ? AppColors.income
                              : AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily spending',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Avg/day ${Money.formatRupees(app.averageDailyExpense.round(), symbol: symbol)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 160,
                        child: _DailyBars(daily: app.dailySpend),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category breakdown',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (app.categoryBreakdown.isEmpty)
                        Text(
                          'No expense categories this month',
                          style: theme.textTheme.bodySmall,
                        )
                      else
                        Row(
                          children: [
                            SizedBox(
                              width: 140,
                              height: 140,
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 36,
                                  sections: app.categoryBreakdown.take(6).map((
                                    c,
                                  ) {
                                    final total = app.monthTotals.expensePaise;
                                    final pct = total == 0
                                        ? 0.0
                                        : c.amountPaise / total * 100;
                                    return PieChartSectionData(
                                      value: c.amountPaise.toDouble(),
                                      color: Color(c.colorValue),
                                      radius: 28,
                                      title: pct >= 8
                                          ? '${pct.toStringAsFixed(0)}%'
                                          : '',
                                      titleStyle: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                children: app.categoryBreakdown
                                    .take(5)
                                    .map(
                                      (c) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Color(c.colorValue),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                c.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                            ),
                                            MoneyText(
                                              c.amountPaise,
                                              symbol: symbol,
                                              compact: true,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'vs previous month',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!app.previousMonthHasData)
                        Text(
                          'Not enough data for a meaningful comparison yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        )
                      else
                        Builder(
                          builder: (_) {
                            final prev = app.previousMonthTotals.expensePaise;
                            final curr = app.monthTotals.expensePaise;
                            final delta = curr - prev;
                            final pct = prev == 0 ? null : (delta / prev) * 100;
                            final up = delta > 0;
                            return Row(
                              children: [
                                Icon(
                                  up
                                      ? Icons.trending_up_rounded
                                      : Icons.trending_down_rounded,
                                  color: up
                                      ? AppColors.expense
                                      : AppColors.income,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    pct == null
                                        ? '${Money.formatRupees(delta.abs(), symbol: symbol)} ${up ? 'more' : 'less'} than last month'
                                        : '${pct.abs().toStringAsFixed(0)}% ${up ? 'higher' : 'lower'} than last month',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Budget utilization',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!app.overallBudgetStatus.isSet)
                        Text(
                          'Set a monthly budget in Settings to track utilization.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        )
                      else ...[
                        MoneyText(
                          app.overallBudgetStatus.spentPaise,
                          symbol: symbol,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'of ${Money.formatRupees(app.overallBudgetStatus.budgetPaise, symbol: symbol)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: app.overallBudgetStatus.utilization
                                .clamp(0, 1)
                                .toDouble(),
                            minHeight: 10,
                            color: app.overallBudgetStatus.warningLevel == 2
                                ? AppColors.danger
                                : app.overallBudgetStatus.warningLevel == 1
                                ? AppColors.warning
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.paise,
    required this.symbol,
    required this.color,
  });

  final String label;
  final int paise;
  final String symbol;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        MoneyText(
          paise,
          symbol: symbol,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    );
  }
}

class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.daily});
  final List<DailySpend> daily;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final maxY = daily
        .map((d) => d.amountPaise.toDouble())
        .fold<double>(1, (a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        maxY: maxY * 1.1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        barGroups: [
          for (var i = 0; i < daily.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: daily[i].amountPaise.toDouble(),
                  width: daily.length > 20 ? 3 : 6,
                  borderRadius: BorderRadius.circular(3),
                  color: primary.withValues(alpha: 0.85),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
