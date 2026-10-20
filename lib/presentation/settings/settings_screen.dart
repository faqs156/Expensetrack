import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/app_settings.dart';
import '../../state/app_controller.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _exportCsv(BuildContext context) async {
    final app = context.read<AppController>();
    try {
      final csv = await app.exportCsv();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/expense_track_export_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      await file.writeAsString(csv);
      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'ExpenseTrack CSV export');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importCsv(BuildContext context) async {
    final app = context.read<AppController>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String? content = file.bytes != null
        ? String.fromCharCodes(file.bytes!)
        : null;
    if (content == null && file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read file')),
      );
      return;
    }
    final importResult = await app.importCsv(content);
    final buf = StringBuffer(
      'Imported ${importResult.imported}, skipped ${importResult.skippedDuplicates}, errors ${importResult.errors}',
    );
    if (importResult.errorMessages.isNotEmpty) {
      buf.write('\n${importResult.errorMessages.join('\n')}');
    }
    messenger.showSnackBar(SnackBar(content: Text(buf.toString())));
  }

  Future<void> _backup(BuildContext context) async {
    try {
      final json = await context.read<AppController>().createBackup();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/expense_track_backup_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(json);
      await Share.shareXFiles([
        XFile(file.path),
      ], subject: 'ExpenseTrack backup');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup created successfully')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    }
  }

  Future<void> _restore(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This replaces all current transactions, categories, budgets, and settings with the backup contents.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    String? content = file.bytes != null
        ? String.fromCharCodes(file.bytes!)
        : null;
    if (content == null && file.path != null) {
      content = await File(file.path!).readAsString();
    }
    if (content == null || !context.mounted) return;
    try {
      await context.read<AppController>().restoreBackup(content);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Backup restored')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Restore failed: $e')));
      }
    }
  }

  Future<void> _clearAll(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all transactions?'),
        content: const Text(
          'This permanently deletes every transaction and budget. Categories and settings are kept. Type CLEAR to confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    final ctrl = TextEditingController();
    final typed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Type CLEAR'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, ctrl.text.trim().toUpperCase() == 'CLEAR'),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (typed == true && context.mounted) {
      await context.read<AppController>().clearAllData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All transaction data cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        Text(
          'Settings',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        Text('Appearance', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<ThemePreference>(
          segments: const [
            ButtonSegment(
              value: ThemePreference.system,
              label: Text('System'),
              icon: Icon(Icons.brightness_auto),
            ),
            ButtonSegment(
              value: ThemePreference.light,
              label: Text('Light'),
              icon: Icon(Icons.light_mode_outlined),
            ),
            ButtonSegment(
              value: ThemePreference.dark,
              label: Text('Dark'),
              icon: Icon(Icons.dark_mode_outlined),
            ),
          ],
          selected: {app.settings.theme},
          onSelectionChanged: (s) {
            app.updateSettings(app.settings.copyWith(theme: s.first));
          },
        ),
        const SizedBox(height: 24),
        Text('Currency', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey(app.settings.currencyCode),
          initialValue: app.settings.currencyCode,
          items: const [
            DropdownMenuItem(value: 'INR', child: Text('INR (₹)')),
            DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
            DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
            DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
          ],
          onChanged: (code) {
            if (code == null) return;
            final symbol = switch (code) {
              'USD' => '\$',
              'EUR' => '€',
              'GBP' => '£',
              _ => '₹',
            };
            app.updateSettings(
              app.settings.copyWith(currencyCode: code, currencySymbol: symbol),
            );
          },
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.category_outlined),
          title: const Text('Manage categories'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CategoriesScreen())),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Budgets'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const BudgetScreen())),
        ),
        const Divider(height: 32),
        Text('Data', style: theme.textTheme.titleSmall),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Export CSV'),
          subtitle: const Text('Transactions with id, date, type, amount…'),
          onTap: () => _exportCsv(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('Import CSV'),
          onTap: () => _importCsv(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Backup data'),
          subtitle: const Text('Full local JSON backup'),
          onTap: () => _backup(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore backup'),
          onTap: () => _restore(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_forever_outlined,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Clear all data',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          onTap: () => _clearAll(context),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.phonelink_lock_outlined),
          title: Text('After uninstall'),
          subtitle: Text(
            'On uninstall, choose “Keep app data” if shown. '
            'A copy is also kept in Documents/ExpenseTrack for restore.',
          ),
        ),
        const Divider(height: 32),
        Text('About', style: theme.textTheme.titleSmall),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline),
          title: Text('ExpenseTrack'),
          subtitle: Text('Version 1.0.0'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Privacy'),
          subtitle: const Text(
            'Data stays on this device. Auto-backup uses local Documents + optional Android backup.',
          ),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Privacy'),
                content: const Text(
                  'ExpenseTrack stores your financial data in a local SQLite database. '
                  'There is no login, advertising, or app cloud sync. '
                  'To survive uninstall, the app writes a backup JSON under Documents/ExpenseTrack '
                  'and can use Android Auto Backup / “Keep app data” when available.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
