import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/google_auth_config.dart';
import '../../state/app_controller.dart';
import '../settings/google_sign_in_button.dart';

/// One-time soft prompt. Never shown again after dismiss, sign-in, or prior session.
class GoogleSignInPromptHost extends StatefulWidget {
  const GoogleSignInPromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<GoogleSignInPromptHost> createState() => _GoogleSignInPromptHostState();
}

class _GoogleSignInPromptHostState extends State<GoogleSignInPromptHost> {
  var _scheduled = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    if (!_scheduled &&
        !app.loading &&
        app.driveSync.ready &&
        GoogleAuthConfig.isConfigured &&
        !app.driveSync.isSignedIn &&
        !app.driveSync.promptDismissed &&
        app.driveSync.lastKnownEmail == null) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPrompt(context);
      });
    }
    return widget.child;
  }

  Future<void> _showPrompt(BuildContext context) async {
    final app = context.read<AppController>();
    // Persist immediately so a refresh / barrier dismiss never re-prompts.
    await app.driveSync.dismissPrompt();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync with Google Drive?'),
        content: const Text(
          'Sign in once with Google to keep the same expenses on every phone '
          'and browser. You can also do this later from Settings.\n\n'
          'You will not be asked again on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GoogleSignInButton(
              onPressed: () async {
                try {
                  await app.signInWithGoogle();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign-in failed: $e')),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
