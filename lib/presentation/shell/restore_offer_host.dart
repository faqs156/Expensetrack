import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_controller.dart';

/// Shows a one-time dialog when a surviving backup is detected after reinstall.
class RestoreOfferHost extends StatefulWidget {
  const RestoreOfferHost({super.key, required this.child});

  final Widget child;

  @override
  State<RestoreOfferHost> createState() => _RestoreOfferHostState();
}

class _RestoreOfferHostState extends State<RestoreOfferHost> {
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.watch<AppController>();
    if (_shown || app.pendingRestoreJson == null || app.loading) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _offer(app));
  }

  Future<void> _offer(AppController app) async {
    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore previous data?'),
        content: const Text(
          'A backup from a previous ExpenseTrack install was found on this device '
          '(Documents/ExpenseTrack). Restore transactions, categories, and budgets?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (restore == true) {
      await app.acceptPendingRestore();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Previous data restored')),
        );
      }
    } else {
      app.dismissRestoreOffer();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
