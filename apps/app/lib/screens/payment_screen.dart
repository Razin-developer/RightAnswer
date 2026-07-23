import 'package:flutter/material.dart';

import '../models/app_exception.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/plans_service.dart';
import 'payment_result_screen.dart';

/// Mock checkout screen — starts a pending payment on entry (so the amount
/// shown always matches what the server would actually charge, per
/// PlansService.checkout), then lets the user simulate a Success or
/// Failure outcome. Swapping in a real gateway later only means replacing
/// the two buttons with that gateway's SDK/redirect; `completePayment` is
/// already the same call a webhook handler would make.
class PaymentScreen extends StatefulWidget {
  final String plan;
  final String planLabel;

  const PaymentScreen({super.key, required this.plan, required this.planLabel});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _startingCheckout = true;
  bool _submitting = false;
  String? _error;
  PlanPayment? _payment;

  @override
  void initState() {
    super.initState();
    _startCheckout();
  }

  Future<void> _startCheckout() async {
    setState(() {
      _startingCheckout = true;
      _error = null;
    });
    try {
      final payment = await PlansService.checkout(widget.plan);
      if (!mounted) return;
      setState(() {
        _payment = payment;
        _startingCheckout = false;
      });
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        AppException(:final message) => message,
        ApiException(:final message) => message,
        _ => 'Could not start checkout. Please try again.',
      };
      setState(() {
        _error = message;
        _startingCheckout = false;
      });
    }
  }

  Future<void> _finish(String status) async {
    final payment = _payment;
    if (payment == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await PlansService.completePayment(payment.id, status);
      if (status == 'success') {
        await AuthService.instance.refreshUser();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaymentResultScreen(
            success: status == 'success',
            planLabel: widget.planLabel,
            amountInr: payment.amountInr,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final message = switch (e) {
        AppException(:final message) => message,
        ApiException(:final message) => message,
        _ => 'Could not complete payment. Please try again.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payment = _payment;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _startingCheckout
                ? const CircularProgressIndicator()
                : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _startCheckout,
                        child: const Text('Try Again'),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Column(
                          children: [
                            Text(
                              widget.planLabel,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₹${payment?.amountInr ?? 0}',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Grants \$${(payment?.creditsUsd ?? 0).toStringAsFixed(2)} in AI credits',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This is a demo checkout — no real payment is collected.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : () => _finish('success'),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('Simulate Success'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : () => _finish('failed'),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Simulate Failure'),
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
