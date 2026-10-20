import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models/app_settings.dart';
import '../../data/services/google_drive_sync_service.dart';
import '../../platform/file_actions.dart';
import '../../state/app_controller.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _driveSyncSubtitle(AppController app) {
    if (app.driveSync.status == DriveSyncStatus.syncing) {
      return 'Syncing…';
    }
    if (app.driveSync.needsGoogleReconnect) {
      return 'Tap Sync now — Google disconnected (phone-only edits)';
    }
    if (app.driveSync.hasPendingPush) {
      return 'Waiting to upload — tap Sync now';
    }
    final last = app.driveSync.lastSyncedAt;
    if (last == null) return 'Signed in';
    final local = last.toLocal();
    return 'Last synced ${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _syncNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final app = context.read<AppController>();
    try {
      await app.syncGoogleDriveNow();
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Sync finished')),
      );
    } catch (_) {
      final msg = app.driveSync.lastError ?? 'Sync failed. Try again.';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final app = context.read<AppController>();
    try {
      final csv = await app.exportCsv();
      final name =
          'expense_track_export_${DateTime.now().millisecondsSinceEpoch}.csv';
      await FileActions.saveTextFile(
        filename: name,
        content: csv,
        mimeType: 'text/csv',
        subject: 'ExpenseTrack CSV export',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'CSV download started ($name). Save this file for your records.'
                  : 'CSV export ready to share.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importCsv(BuildContext context) async {
    final app = context.read<AppController>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final content = await FileActions.pickTextFile(extensions: ['csv', 'txt']);
      if (content == null) return;
      final importResult = await app.importCsv(content);
      final buf = StringBuffer(
        'Imported ${importResult.imported}, skipped ${importResult.skippedDuplicates}, errors ${importResult.errors}',
      );
      if (importResult.errorMessages.isNotEmpty) {
        buf.write('\n${importResult.errorMessages.join('\n')}');
      }
      messenger.showSnackBar(SnackBar(content: Text(buf.toString())));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _backup(BuildContext context) async {
    try {
      final json = await context.read<AppController>().createBackup();
      final name =
          'expense_track_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      await FileActions.saveTextFile(
        filename: name,
        content: json,
        mimeType: 'application/json',
        subject: 'ExpenseTrack backup',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb
                  ? 'Backup file download started. Keep $name somewhere safe — browser storage can be cleared.'
                  : 'Backup created successfully. Keep the shared file safe.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $e')),
        );
      }
    }
  }

  Future<void> _restore(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This replaces all current transactions, categories, budgets, and settings with the backup contents. This cannot be undone.',
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

    try {
      final content = await FileActions.pickTextFile(extensions: ['json']);
      if (content == null || !context.mounted) return;
      await context.read<AppController>().restoreBackup(content);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e')),
        );
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
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CategoriesScreen()),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('Budgets'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BudgetScreen()),
          ),
        ),
        const Divider(height: 32),
        Text('Account', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: Text(app.driveSync.email ?? 'Signed in'),
          subtitle: Text(_driveSyncSubtitle(app)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: app.driveSync.status == DriveSyncStatus.syncing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  app.driveSync.needsGoogleReconnect
                      ? Icons.cloud_sync_outlined
                      : Icons.sync,
                ),
          title: const Text('Sync now'),
          subtitle: Text(
            app.driveSync.status == DriveSyncStatus.syncing
                ? 'Syncing…'
                : app.driveSync.hasPendingPush
                    ? 'Uploading changes…'
                    : 'Download & upload with Google Drive',
          ),
          onTap: app.driveSync.status == DriveSyncStatus.syncing
              ? null
              : () => _syncNow(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('When data is saved'),
          subtitle: Text(
            kIsWeb
                ? 'Local: instantly + safety snapshot on this device. '
                    'Drive: ~2s after edits, every 5 min, and before sign-out. Sync merges devices and keeps a previous Drive copy.'
                : 'Phone: instantly in the app DB + safety snapshot. '
                    'Drive: ~2s after edits, every 5 min, and before sign-out. Sync merges devices and keeps a previous Drive copy.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          subtitle: const Text(
            'Uploads your data first; keeps it on this device',
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            messenger.showSnackBar(
              const SnackBar(content: Text('Saving to Drive, then signing out…')),
            );
            await context.read<AppController>().signOutGoogle();
          },
        ),
        if (app.driveSync.lastError != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.info_outline,
              color: theme.colorScheme.tertiary,
            ),
            title: Text(
              app.driveSync.lastError!,
              style: theme.textTheme.bodySmall,
            ),
            trailing: IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close),
              onPressed: () => app.driveSync.clearLastError(),
            ),
          ),
        const Divider(height: 32),
        Text('Data', style: theme.textTheme.titleSmall),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Export CSV'),
          subtitle: Text(
            kIsWeb
                ? 'Downloads a CSV you can save or import later'
                : 'Transactions with id, date, type, amount…',
          ),
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
          subtitle: Text(
            kIsWeb
                ? 'Downloads a JSON backup file (not automatic cloud backup)'
                : 'Full local JSON backup file',
          ),
          onTap: () => _backup(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore backup'),
          subtitle: const Text('Requires a previously downloaded JSON file'),
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.phonelink_lock_outlined),
          title: const Text('Where data lives'),
          subtitle: Text(
            'Stored on this device and synced with your Google account.',
          ),
        ),
        const Divider(height: 32),
        Text('About', style: theme.textTheme.titleSmall),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.info_outline),
          title: Text('ExpenseTrack'),
          subtitle: Text('Version 1.0.0 · Offline personal finance'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Privacy'),
          subtitle: const Text('No ads. Your data stays with your Google account.'),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Privacy'),
                content: const Text(
                  'ExpenseTrack stores data on this device and can sync it with '
                  'your Google account. There are no ads or analytics.',
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
