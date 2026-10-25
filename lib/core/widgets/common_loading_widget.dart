import 'package:flutter/material.dart';

class CommonLoadingWidget extends StatelessWidget {
  final String message;

  final VoidCallback? onRetry;

  const CommonLoadingWidget({
    super.key,
    this.message = 'লোড হচ্ছে…',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: onRetry,
              child: const Text('আবার চেষ্টা করুন'),
            ),
          ],
        ],
      ),
    );
  }
}
