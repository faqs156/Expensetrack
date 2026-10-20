import 'package:flutter/material.dart';

/// Non-web platforms use a normal button (see [GoogleSignInButton]).
Widget buildGoogleSignInButton({required VoidCallback onPressed}) {
  return FilledButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.login),
    label: const Text('Sign in with Google'),
  );
}
