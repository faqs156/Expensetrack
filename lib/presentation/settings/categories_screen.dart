import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/category.dart';
import '../../data/repositories/category_repository.dart';
import '../../state/app_controller.dart';
import '../widgets/category_icon.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  Future<void> _add(BuildContext context, CategoryKind kind) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          kind == CategoryKind.expense
              ? 'New expense category'
              : 'New income category',
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Category name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<AppController>().createCategory(
        name: name,
        kind: kind,
      );
    }
  }

  Future<void> _rename(BuildContext context, ExpenseCategory cat) async {
    final ctrl = TextEditingController(text: cat.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<AppController>().renameCategory(cat.id, name);
    }
  }

  Future<void> _delete(BuildContext context, ExpenseCategory cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove category?'),
        content: Text(
          cat.isDefault
              ? 'Default categories with transactions will be archived instead of deleted, so history is preserved.'
              : 'If this category has transactions, it will be archived rather than permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final result = await context.read<AppController>().deleteCategory(cat.id);
    if (!context.mounted) return;
    final msg = switch (result) {
      DeleteCategoryResult.deleted => 'Category deleted',
      DeleteCategoryResult.archived => 'Category archived — transactions kept',
      DeleteCategoryResult.notFound => 'Category not found',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final expenses = app.categories
        .where((c) => c.kind == CategoryKind.expense)
        .toList();
    final incomes = app.categories
        .where((c) => c.kind == CategoryKind.income)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SectionHeader(
            title: 'Expenses',
            onAdd: () => _add(context, CategoryKind.expense),
          ),
          ...expenses.map(
            (c) => ListTile(
              leading: CategoryIcon(
                iconKey: c.iconKey,
                colorValue: c.colorValue,
              ),
              title: Text(c.name),
              subtitle: c.isArchived ? const Text('Archived') : null,
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'rename') _rename(context, c);
                  if (v == 'delete') _delete(context, c);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(
            title: 'Income',
            onAdd: () => _add(context, CategoryKind.income),
          ),
          ...incomes.map(
            (c) => ListTile(
              leading: CategoryIcon(
                iconKey: c.iconKey,
                colorValue: c.colorValue,
              ),
              title: Text(c.name),
              subtitle: c.isArchived ? const Text('Archived') : null,
              trailing: PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'rename') _rename(context, c);
                  if (v == 'delete') _delete(context, c);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onAdd});
  final String title;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
      ],
    );
  }
}
