import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as gsi;

/// Official GIS button required on Flutter web.
Widget buildGoogleSignInButton({required VoidCallback onPressed}) {
  // [onPressed] unused on web — GIS button owns the click; sync follows auth events.
  return gsi.renderButton();
}
