import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/google_auth_config.dart';
import '../../state/app_controller.dart';
import '../settings/google_sign_in_button.dart';

/// Soft prompt once per browser profile asking the user to sign in for Drive sync.
class GoogleSignInPromptHost extends StatefulWidget {
  const GoogleSignInPromptHost({super.key, required this.child});

  final Widget child;

  @override
  State<GoogleSignInPromptHost> createState() => _GoogleSignInPromptHostState();
}

class _GoogleSignInPromptHostState extends State<GoogleSignInPromptHost> {
  var _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    final app = context.read<AppController>();
    if (!GoogleAuthConfig.isConfigured) return;
    if (app.driveSync.isSignedIn || app.driveSync.promptDismissed) return;
    if (app.loading) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showPrompt(context);
    });
  }

  Future<void> _showPrompt(BuildContext context) async {
    final app = context.read<AppController>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync with Google Drive?'),
        content: const Text(
          'Sign in with Google to keep the same expenses on every phone and browser '
          'that uses this account. Data is stored in a private Drive app folder '
          '(not visible in My Drive).\n\n'
          'You can skip and keep data only on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await app.driveSync.dismissPrompt();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Not now'),
          ),
          if (app.driveSync.isSignedIn)
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            )
          else ...[
            if (!app.driveSync.isSignedIn)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GoogleSignInButton(
                  onPressed: () async {
                    try {
                      await app.signInWithGoogle();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Sign-in failed: $e')),
                        );
                      }
                    }
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
