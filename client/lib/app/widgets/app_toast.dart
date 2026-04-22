import 'package:flutter/material.dart';

class AppToast {
  static void show(BuildContext context, String message, {bool error = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFFB84040)
            : const Color(0xFF136C4E),
      ),
    );
  }
}
