import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/transaction.dart';
import '../../state/app_controller.dart';
import '../widgets/category_icon.dart';

class AddEditTransactionScreen extends StatefulWidget {
  const AddEditTransactionScreen({super.key, this.existing});

  final Transaction? existing;

  @override
  State<AddEditTransactionScreen> createState() =>
      _AddEditTransactionScreenState();
}

class _AddEditTransactionScreenState extends State<AddEditTransactionScreen> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late TxType _type;
  String? _categoryId;
  late DateTime _occurredAt;
  PaymentMethod _payment = PaymentMethod.upi;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? TxType.expense;
    _categoryId = e?.categoryId;
    _occurredAt = e?.occurredAt ?? DateTime.now();
    _payment = e?.paymentMethod ?? PaymentMethod.upi;
    if (e != null) {
      _amountCtrl.text = Money.paiseToRupees(e.amountPaise).toStringAsFixed(2);
      _descCtrl.text = e.description ?? '';
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null || !mounted) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final amount = Money.parseToPaise(_amountCtrl.text);
    if (amount == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    if (_categoryId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a category')));
      return;
    }

    setState(() => _saving = true);
    final app = context.read<AppController>();
    try {
      if (_isEdit) {
        await app.updateTransaction(
          widget.existing!.copyWith(
            amountPaise: amount,
            type: _type,
            categoryId: _categoryId!,
            occurredAt: _occurredAt,
            paymentMethod: _payment,
            description: _descCtrl.text.trim(),
          ),
        );
      } else {
        await app.addTransaction(
          amountPaise: amount,
          type: _type,
          categoryId: _categoryId!,
          occurredAt: _occurredAt,
          paymentMethod: _payment,
          description: _descCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Transaction updated' : 'Transaction saved'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final cats = app.categoriesFor(_type);
    if (_categoryId != null && !cats.any((c) => c.id == _categoryId)) {
      _categoryId = null;
    }
    _categoryId ??= cats.isNotEmpty ? cats.first.id : null;

    final theme = Theme.of(context);
    final symbol = app.settings.currencySymbol;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit transaction' : 'Add transaction'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'Amount',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _amountCtrl,
              autofocus: !_isEdit,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
              decoration: InputDecoration(
                prefixText: '$symbol ',
                prefixStyle: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
                hintText: '0.00',
              ),
              validator: (v) {
                final p = Money.parseToPaise(v ?? '');
                if (p == null) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SegmentedButton<TxType>(
              segments: const [
                ButtonSegment(
                  value: TxType.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.south_west_rounded),
                ),
                ButtonSegment(
                  value: TxType.income,
                  label: Text('Income'),
                  icon: Icon(Icons.north_east_rounded),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() {
                  _type = s.first;
                  _categoryId = null;
                });
              },
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _type == TxType.expense
                        ? AppColors.expense
                        : AppColors.income;
                  }
                  return null;
                }),
              ),
            ),
            const SizedBox(height: 24),
            Text('Category', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cats.map((c) {
                final selected = c.id == _categoryId;
                return ChoiceChip(
                  selected: selected,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CategoryIcon(
                        iconKey: c.iconKey,
                        colorValue: c.colorValue,
                        size: 28,
                      ),
                      const SizedBox(width: 8),
                      Text(c.name),
                    ],
                  ),
                  onSelected: (_) => setState(() => _categoryId = c.id),
                  showCheckmark: false,
                  selectedColor: Color(c.colorValue).withValues(alpha: 0.18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Date & time'),
              subtitle: Text(
                DateFormat('EEE, d MMM yyyy · h:mm a').format(_occurredAt),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 8),
            Text('Payment method', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: PaymentMethod.values.map((p) {
                return ChoiceChip(
                  label: Text(p.label),
                  selected: _payment == p,
                  onSelected: (_) => setState(() => _payment = p),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _descCtrl,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                counterText: '',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEdit ? 'Update' : 'Save transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
