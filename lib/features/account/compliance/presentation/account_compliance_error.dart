import 'package:flutter/material.dart';

/// Shared fail-closed state for account pages whose authoritative data could
/// not be loaded.  Account pages must never leave a failed request looking
/// like an in-progress spinner or an empty, healthy account.
class AccountComplianceError extends StatelessWidget {
  const AccountComplianceError({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 42),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

/// Makes mutation failures recoverable without pretending the write succeeded.
/// The retry remains at the presentation boundary so the repository can keep
/// its fail-closed response validation.
void showAccountComplianceRetrySnackBar(
  BuildContext context, {
  required String message,
  required VoidCallback onRetry,
}) {
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      action: SnackBarAction(label: '重试', onPressed: onRetry),
    ),
  );
}
