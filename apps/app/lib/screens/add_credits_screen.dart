import 'package:flutter/material.dart';

import '../utils/currency.dart';
import 'payment_screen.dart';

const _coral = Color(0xFFCC785C);

/// Lets the user buy a standalone AI-credit top-up in USD (separate from
/// upgrading a plan tier) — reuses the same mock PaymentScreen flow, just
/// with `plan: 'credits'` and the chosen amount.
class AddCreditsScreen extends StatefulWidget {
  const AddCreditsScreen({super.key});

  @override
  State<AddCreditsScreen> createState() => _AddCreditsScreenState();
}

class _AddCreditsScreenState extends State<AddCreditsScreen> {
  static const _presets = [1.0, 5.0, 10.0, 25.0];
  double _selectedUsd = 5.0;
  final _customCtrl = TextEditingController();
  bool _useCustom = false;

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  double? get _amountUsd {
    if (!_useCustom) return _selectedUsd;
    return double.tryParse(_customCtrl.text.trim());
  }

  void _continue() {
    final usd = _amountUsd;
    if (usd == null || usd < 0.5 || usd > 100) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Enter an amount between \$0.50 and \$100')),
        );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          plan: 'credits',
          planLabel: 'AI Credit Top-up',
          creditsUsd: usd,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usd = _amountUsd;
    final inr = usd == null ? null : Currency.inr.usdToLocalRounded(usd);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Credits'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Top up AI credit in dollars — it tops up your weekly allowance and is used automatically once your plan limit is reached.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final preset in _presets)
                ChoiceChip(
                  label: Text('\$${preset.toStringAsFixed(0)}'),
                  selected: !_useCustom && _selectedUsd == preset,
                  onSelected: (_) => setState(() {
                    _useCustom = false;
                    _selectedUsd = preset;
                  }),
                ),
              ChoiceChip(
                label: const Text('Custom'),
                selected: _useCustom,
                onSelected: (_) => setState(() => _useCustom = true),
              ),
            ],
          ),
          if (_useCustom) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _customCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount in USD',
                prefixText: r'$ ',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Column(
              children: [
                Text(
                  usd == null ? '—' : '\$${usd.toStringAsFixed(2)}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _coral,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  inr == null ? '' : 'Charged as ₹$inr',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _continue,
              child: const Text('Continue to Payment'),
            ),
          ),
        ],
      ),
    );
  }
}
