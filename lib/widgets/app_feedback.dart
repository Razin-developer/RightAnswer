import 'package:flutter/material.dart';

import '../models/app_exception.dart';

class AppFeedback {
  AppFeedback._();

  static void showToast(
    BuildContext context,
    String message, {
    Color? backgroundColor,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  static Future<void> showErrorDialog(
    BuildContext context,
    Object error, {
    String? actionLabel,
    VoidCallback? onAction,
  }) async {
    final appError = AppException.from(error);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appError.title),
        content: Text(appError.message),
        actions: [
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onAction();
              },
              child: Text(actionLabel),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
