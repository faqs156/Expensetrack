import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/date_keys.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../state/app_controller.dart';
import '../widgets/category_icon.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/soft_card.dart';
import 'add_edit_transaction_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final app = context.read<AppController>();
    var filter = app.txFilter;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                20 + MediaQuery.paddingOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Filters',
                    style: Theme.of(ctx).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  Text('Type', style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: filter.type == null,
                        onSelected: (_) => setModal(
                          () => filter = filter.copyWith(clearType: true),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Expense'),
                        selected: filter.type == TxType.expense,
                        onSelected: (_) => setModal(
                          () => filter = filter.copyWith(type: TxType.expense),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Income'),
                        selected: filter.type == TxType.income,
                        onSelected: (_) => setModal(
                          () => filter = filter.copyWith(type: TxType.income),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Category', style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(filter.categoryId),
                    initialValue: filter.categoryId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ...app.categories.map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ),
                    ],
                    onChanged: (v) => setModal(() {
                      filter = v == null
                          ? filter.copyWith(clearCategory: true)
                          : filter.copyWith(categoryId: v);
                    }),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final range = await showDateRangePicker(
                              context: ctx,
                              firstDate: DateTime(2000),
                              lastDate: DateTime.now().add(
                                const Duration(days: 1),
                              ),
                              initialDateRange:
                                  filter.from != null && filter.to != null
                                  ? DateTimeRange(
                                      start: filter.from!,
                                      end: filter.to!,
                                    )
                                  : null,
                            );
                            if (range != null) {
                              setModal(() {
                                filter = filter.copyWith(
                                  from: range.start,
                                  to: range.end,
                                );
                              });
                            }
                          },
                          child: Text(
                            filter.from == null
                                ? 'Date range'
                                : '${DateFormat('d MMM').format(filter.from!)} – ${DateFormat('d MMM').format(filter.to!)}',
                          ),
                        ),
                      ),
                      if (filter.from != null)
                        IconButton(
                          onPressed: () => setModal(() {
                            filter = filter.copyWith(
                              clearFrom: true,
                              clearTo: true,
                            );
                          }),
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Sort', style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Date'),
                        selected: filter.sort == TxSort.date,
                        onSelected: (_) => setModal(
                          () => filter = filter.copyWith(sort: TxSort.date),
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Amount'),
                        selected: filter.sort == TxSort.amount,
                        onSelected: (_) => setModal(
                          () => filter = filter.copyWith(sort: TxSort.amount),
                        ),
                      ),
                      ChoiceChip(
                        label: Text(filter.ascending ? 'Asc' : 'Desc'),
                        selected: true,
                        onSelected: (_) => setModal(
                          () => filter = filter.copyWith(
                            ascending: !filter.ascending,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      app.setTxFilter(filter);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(Transaction tx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AppController>().deleteTransaction(tx.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Transaction deleted')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);
    final symbol = app.settings.currencySymbol;
    final items = app.filteredTransactions;

    final grouped = <String, List<Transaction>>{};
    for (final t in items) {
      final key = DateKeys.dayKey(t.occurredAt);
      grouped.putIfAbsent(key, () => []).add(t);
    }
    final keys = grouped.keys.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transactions',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: const InputDecoration(
                        hintText: 'Search description',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) {
                        app.setTxFilter(app.txFilter.copyWith(search: v));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _openFilters,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SoftCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Expenses', style: theme.textTheme.labelMedium),
                          MoneyText(
                            app.filteredTotals.expensePaise,
                            symbol: symbol,
                            isIncome: false,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Income', style: theme.textTheme.labelMedium),
                          MoneyText(
                            app.filteredTotals.incomePaise,
                            symbol: symbol,
                            isIncome: true,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${items.length}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions',
                  message: 'Try adjusting filters, or add a new transaction with the + button.',
                  actionLabel: 'Clear filters',
                  onAction: () {
                    _search.clear();
                    app.setTxFilter(const TransactionFilter());
                  },
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  itemCount: keys.length,
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    final dayItems = grouped[key]!;
                    final day = dayItems.first.occurredAt;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Text(
                            DateFormat('EEE, d MMM yyyy').format(day),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        ...dayItems.map((t) {
                          final isIncome = t.type == TxType.income;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Dismissible(
                              key: ValueKey(t.id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _confirmDelete(t);
                                return false;
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                              ),
                              child: SoftCard(
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddEditTransactionScreen(existing: t),
                                    ),
                                  );
                                },
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  children: [
                                    CategoryIcon(
                                      iconKey: t.categoryIconKey ?? 'custom',
                                      colorValue: t.categoryColor ?? 0xFF64748B,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.description?.isNotEmpty == true
                                                ? t.description!
                                                : (t.categoryName ??
                                                      'Transaction'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          Text(
                                            '${t.categoryName} · ${t.paymentMethod.label} · ${DateFormat('h:mm a').format(t.occurredAt)}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.5),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    MoneyText(
                                      t.amountPaise,
                                      symbol: symbol,
                                      signed: true,
                                      isIncome: isIncome,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
