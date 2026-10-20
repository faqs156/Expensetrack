import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/models/app_settings.dart';
import 'presentation/shell/google_sign_in_prompt.dart';
import 'presentation/shell/main_shell.dart';
import 'presentation/shell/restore_offer_host.dart';
import 'state/app_controller.dart';

class ExpenseTrackApp extends StatelessWidget {
  const ExpenseTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppController()..init(),
      child: const _AppView(),
    );
  }
}

class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppController>().settings;
    final loading = context.watch<AppController>().loading;
    final error = context.watch<AppController>().error;

    final mode = switch (settings.theme) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.system => ThemeMode.system,
    };

    return MaterialApp(
      title: 'ExpenseTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: loading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : error != null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to start: $error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => context.read<AppController>().init(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const GoogleSignInPromptHost(
              child: RestoreOfferHost(child: MainShell()),
            ),
    );
  }
}
