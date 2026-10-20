import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/category.dart';
import '../../state/app_controller.dart';
import '../widgets/category_icon.dart';
import '../widgets/soft_card.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final _overall = TextEditingController();

  @override
  void initState() {
    super.initState();
    final app = context.read<AppController>();
    final paise = app.overallBudgetStatus.budgetPaise > 0
        ? app.overallBudgetStatus.budgetPaise
        : app.settings.defaultOverallBudgetPaise;
    if (paise > 0) {
      _overall.text = Money.paiseToRupees(paise).toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _overall.dispose();
    super.dispose();
  }

  Future<void> _saveOverall() async {
    final paise = Money.parseToPaise(_overall.text, allowZero: true) ?? 0;
    await context.read<AppController>().setOverallBudget(paise);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Budget saved')));
    }
  }

  Future<void> _editCategoryBudget(ExpenseCategory cat) async {
    final app = context.read<AppController>();
    final current = app.budget.categoryPaise[cat.id] ?? 0;
    final ctrl = TextEditingController(
      text: current > 0 ? Money.paiseToRupees(current).toStringAsFixed(0) : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${cat.name} budget'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            prefixText: '${app.settings.currencySymbol} ',
            hintText: '0 to clear',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final p = Money.parseToPaise(ctrl.text, allowZero: true) ?? 0;
              Navigator.pop(ctx, p);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      await app.setCategoryBudget(cat.id, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);
    final symbol = app.settings.currencySymbol;
    final expenses = app.categories
        .where((c) => c.kind == CategoryKind.expense && !c.isArchived)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Text(
            'Month: ${DateFormat('MMMM yyyy').format(app.selectedMonth)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall monthly budget',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _overall,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    prefixText: '$symbol ',
                    hintText: 'e.g. 50000',
                  ),
                ),
                const SizedBox(height: 12),
                if (app.overallBudgetStatus.isSet) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: app.overallBudgetStatus.utilization
                          .clamp(0, 1)
                          .toDouble(),
                      minHeight: 8,
                      color: app.overallBudgetStatus.warningLevel == 2
                          ? AppColors.danger
                          : app.overallBudgetStatus.warningLevel == 1
                          ? AppColors.warning
                          : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${Money.formatRupees(app.overallBudgetStatus.spentPaise, symbol: symbol)} spent · ${Money.formatRupees(app.overallBudgetStatus.remainingPaise, symbol: symbol)} left',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _saveOverall,
                  child: const Text('Save overall budget'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Category budgets (optional)',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ...expenses.map((c) {
            final status = app.categoryBudgetStatus(c.id);
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CategoryIcon(
                iconKey: c.iconKey,
                colorValue: c.colorValue,
              ),
              title: Text(c.name),
              subtitle: Text(
                status.isSet
                    ? '${Money.formatRupees(status.spentPaise, symbol: symbol)} / ${Money.formatRupees(status.budgetPaise, symbol: symbol)}'
                    : 'Not set',
              ),
              trailing: status.isSet && status.warningLevel > 0
                  ? Icon(
                      Icons.warning_amber_rounded,
                      color: status.warningLevel == 2
                          ? AppColors.danger
                          : AppColors.warning,
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: () => _editCategoryBudget(c),
            );
          }),
        ],
      ),
    );
  }
}
