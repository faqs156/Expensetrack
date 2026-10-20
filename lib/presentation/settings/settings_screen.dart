import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/google_auth_config.dart';
import '../../data/models/app_settings.dart';
import '../../data/services/google_drive_sync_service.dart';
import '../../platform/file_actions.dart';
import '../../state/app_controller.dart';
import 'budget_screen.dart';
import 'categories_screen.dart';
import 'google_sign_in_button.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _driveSyncSubtitle(AppController app) {
    if (!app.driveSync.isSignedIn) {
      return 'Same Google account → same vault on every device & browser';
    }
    final last = app.driveSync.lastSyncedAt;
    if (app.driveSync.status == DriveSyncStatus.syncing) {
      return 'Syncing with Google Drive…';
    }
    if (last == null) return 'Signed in — tap Sync now';
    final local = last.toLocal();
    return 'Last synced ${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _signInGoogle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppController>().signInWithGoogle();
      messenger.showSnackBar(
        const SnackBar(content: Text('Signed in — Drive sync ready')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    }
  }

  Future<void> _syncNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppController>().syncGoogleDriveNow();
      messenger.showSnackBar(
        const SnackBar(content: Text('Google Drive sync finished')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Sync failed: $e')));
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
        Text('Google Drive sync', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (!GoogleAuthConfig.isConfigured)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_off_outlined),
            title: const Text('Google sync not configured'),
            subtitle: const Text(
              'Build with --dart-define=GOOGLE_CLIENT_ID=… and enable '
              'Drive API (see README).',
            ),
          )
        else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              app.driveSync.isSignedIn
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_outlined,
            ),
            title: Text(
              app.driveSync.isSignedIn
                  ? (app.driveSync.email ?? 'Signed in')
                  : 'Not signed in',
            ),
            subtitle: Text(_driveSyncSubtitle(app)),
          ),
          if (!app.driveSync.isSignedIn)
            Align(
              alignment: Alignment.centerLeft,
              child: GoogleSignInButton(
                onPressed: () => _signInGoogle(context),
              ),
            )
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: app.driveSync.status == DriveSyncStatus.syncing
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              title: const Text('Sync now'),
              subtitle: const Text('Pull newer Drive data or upload this device'),
              onTap: app.driveSync.status == DriveSyncStatus.syncing
                  ? null
                  : () => _syncNow(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout),
              title: const Text('Sign out of Google'),
              subtitle: const Text('Keeps Drive backup; stops auto-sync here'),
              onTap: () async {
                await context.read<AppController>().signOutGoogle();
              },
            ),
          ],
          if (app.driveSync.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                app.driveSync.lastError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
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
            kIsWeb
                ? (app.driveSync.isSignedIn
                    ? 'Signed in: vault syncs via Google Drive app data for this account. '
                        'Local copy still works offline.'
                    : 'Without Google: one vault per browser on this phone. '
                        'Sign in above to share across devices & Chrome/Safari.')
                : 'SQLite on this device only. Uninstall may wipe data unless you keep app data or restore a backup.',
          ),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Your vault'),
                content: Text(
                  app.driveSync.isSignedIn
                      ? 'Signed in with Google. ExpenseTrack uploads a private sync file to '
                          'Google Drive app data (hidden from My Drive). The same account on '
                          'another phone or browser downloads that file — last write wins.\n\n'
                          'Offline edits stay local until the next sync.'
                      : 'Local saves stay in this browser only.\n\n'
                          'Sign in with Google (Settings → Google Drive sync) to use the same '
                          'vault on every device with that account. Or use Backup / Restore JSON.',
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
          subtitle: Text(
            app.driveSync.isSignedIn
                ? 'Optional Google Drive sync. No ads. Local SQLite + private Drive app file.'
                : 'Optional Google sign-in for Drive sync. Otherwise data stays on this device.',
          ),
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Privacy'),
                content: Text(
                  kIsWeb
                      ? 'Local data: SQLite in this browser (IndexedDB). '
                          'Optional: sign in with Google to sync a private file in Drive app data '
                          '(same Google account → same vault). We do not run our own server. '
                          'Safari may clear site data — Drive sync or JSON backups protect you.'
                      : 'Local SQLite on device. Optional Google Drive app-data sync when signed in. '
                          'No advertising SDKs.',
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
