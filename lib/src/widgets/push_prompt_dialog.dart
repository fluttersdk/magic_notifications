import 'package:flutter/material.dart';

/// A dialog that prompts the user to enable push notifications.
///
/// This is a "soft" prompt that appears before requesting system permission,
/// allowing the app to explain why push notifications are useful.
class PushPromptDialog extends StatelessWidget {
  /// The dialog title.
  final String title;

  /// The dialog message explaining why notifications are useful.
  final String message;

  /// Text for the accept button (e.g., "Enable").
  final String acceptText;

  /// Text for the decline button (e.g., "Not Now").
  final String declineText;

  /// Callback when user accepts (wants to enable notifications).
  final VoidCallback onAccept;

  /// Callback when user declines.
  final VoidCallback onDecline;

  const PushPromptDialog({
    super.key,
    this.title = 'Enable Notifications',
    this.message = 'Stay updated with important alerts and notifications.',
    this.acceptText = 'Enable',
    this.declineText = 'Not Now',
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: onDecline,
          child: Text(declineText),
        ),
        ElevatedButton(
          onPressed: onAccept,
          child: Text(acceptText),
        ),
      ],
    );
  }
}
