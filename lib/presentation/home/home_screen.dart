import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/date_keys.dart';
import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../state/app_controller.dart';
import '../transactions/add_edit_transaction_screen.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/soft_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);
    final symbol = app.settings.currencySymbol;
    final monthLabel = DateFormat('MMMM yyyy').format(app.selectedMonth);
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
                  _greeting(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, d MMMM').format(DateTime.now()),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                if (app.needsDriveUploadAttention || app.needsCloudPull) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(
                        children: [
                          Icon(
                            app.needsDriveUploadAttention
                                ? Icons.cloud_upload_outlined
                                : Icons.cloud_download_outlined,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              app.needsDriveUploadAttention
                                  ? (app.driveSync.needsGoogleReconnect
                                      ? 'Google disconnected — edits are only on this device until you Sync.'
                                      : 'Edits saved here but not confirmed on Drive yet. Sync so Mac can see them.')
                                  : 'No data on this device yet. Sync to load it.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await context
                                    .read<AppController>()
                                    .syncGoogleDriveNow();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Sync finished'),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  final msg = context
                                          .read<AppController>()
                                          .driveSync
                                          .lastError ??
                                      'Sync failed. Try again.';
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(msg)),
                                  );
                                }
                              }
                            },
                            child: const Text('Sync'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
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
                        monthLabel,
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
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No activity yet',
              message:
                  'Track your first expense or income for $monthLabel to see totals and trends here.',
              actionLabel: 'Add transaction',
              onAction: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const AddEditTransactionScreen(),
                  ),
                );
              },
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            sliver: SliverList.list(
              children: [
                SoftCard(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total expenses',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      MoneyText(
                        app.monthTotals.expensePaise,
                        symbol: symbol,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          color: AppColors.expense,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Income',
                              paise: app.monthTotals.incomePaise,
                              symbol: symbol,
                              color: AppColors.income,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _MiniStat(
                              label: 'Budget left',
                              paise: app.overallBudgetStatus.isSet
                                  ? app.overallBudgetStatus.remainingPaise
                                  : 0,
                              symbol: symbol,
                              color: app.overallBudgetStatus.warningLevel == 2
                                  ? AppColors.danger
                                  : app.overallBudgetStatus.warningLevel == 1
                                  ? AppColors.warning
                                  : theme.colorScheme.primary,
                              subtitle: app.overallBudgetStatus.isSet
                                  ? '${(app.overallBudgetStatus.utilization * 100).clamp(0, 999).toStringAsFixed(0)}% used'
                                  : 'No budget set',
                            ),
                          ),
                        ],
                      ),
                      if (app.overallBudgetStatus.isSet) ...[
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: app.overallBudgetStatus.utilization
                                .clamp(0, 1)
                                .toDouble(),
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
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
                const SizedBox(height: 16),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Spending trend',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 140,
                        child: _TrendChart(daily: app.dailySpend),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'By category',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...app.categoryBreakdown.take(5).map((c) {
                        final pct = app.monthTotals.expensePaise == 0
                            ? 0.0
                            : c.amountPaise / app.monthTotals.expensePaise;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              CategoryIcon(
                                iconKey: c.iconKey,
                                colorValue: c.colorValue,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: pct.clamp(0, 1),
                                        minHeight: 5,
                                        backgroundColor: Color(c.colorValue)
                                            .withValues(alpha: 0.12),
                                        color: Color(c.colorValue),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              MoneyText(
                                c.amountPaise,
                                symbol: symbol,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Recent',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            fullscreenDialog: true,
                            builder: (_) => const AddEditTransactionScreen(),
                          ),
                        );
                      },
                      child: const Text('Quick add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...app.recent.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TxTile(tx: t, symbol: symbol),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.paise,
    required this.symbol,
    required this.color,
    this.subtitle,
  });

  final String label;
  final int paise;
  final String symbol;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          MoneyText(
            paise,
            symbol: symbol,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
            compact: true,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.daily});
  final List<DailySpend> daily;

  @override
  Widget build(BuildContext context) {
    if (daily.every((d) => d.amountPaise == 0)) {
      return Center(
        child: Text(
          'No expense trend for this month',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final maxY = daily
        .map((d) => d.amountPaise.toDouble())
        .fold<double>(0, (a, b) => a > b ? a : b);
    final spots = <FlSpot>[];
    for (var i = 0; i < daily.length; i++) {
      spots.add(FlSpot(i.toDouble(), daily[i].amountPaise.toDouble()));
    }
    final primary = Theme.of(context).colorScheme.primary;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched
                .map(
                  (s) => LineTooltipItem(
                    Money.formatRupees(s.y.round()),
                    TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primary,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, required this.symbol});
  final Transaction tx;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = tx.type == TxType.income;
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddEditTransactionScreen(existing: tx),
          ),
        );
      },
      child: Row(
        children: [
          CategoryIcon(
            iconKey: tx.categoryIconKey ?? 'custom',
            colorValue: tx.categoryColor ?? 0xFF64748B,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.description?.isNotEmpty == true
                      ? tx.description!
                      : (tx.categoryName ?? 'Transaction'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${tx.categoryName ?? ''} · ${tx.paymentMethod.label}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          MoneyText(
            tx.amountPaise,
            symbol: symbol,
            signed: true,
            isIncome: isIncome,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
