import 'package:flutter/material.dart';

import 'main_screen.dart';

/// Terminal screen for the mock checkout flow — renders either the success
/// or failure state depending on [success]. A real payment gateway
/// integration would land here from a webhook-driven redirect instead of
/// PaymentScreen's Simulate buttons; the screen itself doesn't change.
class PaymentResultScreen extends StatelessWidget {
  final bool success;
  final String planLabel;
  final int amountInr;

  const PaymentResultScreen({
    super.key,
    required this.success,
    required this.planLabel,
    required this.amountInr,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  success
                      ? Icons.check_circle_outline_rounded
                      : Icons.cancel_outlined,
                  size: 72,
                  color: success
                      ? const Color(0xFF059669)
                      : const Color(0xFFDC2626),
                ),
                const SizedBox(height: 20),
                Text(
                  success ? 'Payment Successful' : 'Payment Failed',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  success
                      ? "You're now on the $planLabel plan. Increased limits are active immediately."
                      : 'Your payment of ₹$amountInr for $planLabel could not be completed. No charge was made.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const MainScreen()),
                      (_) => false,
                    ),
                    child: Text(success ? 'Continue' : 'Back to App'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
