import 'package:flutter/material.dart';

import '../screens/plans_screen.dart';

/// Upsell shown in place of a feature's real content when the signed-in
/// user's plan doesn't include it (e.g. Study Plans on the free Hobby
/// tier). Never blocks navigation entirely — just replaces the body with a
/// clear explanation and a direct path to upgrade.
class PlanGate extends StatelessWidget {
  final String featureName;
  final String? description;

  const PlanGate({super.key, required this.featureName, this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '$featureName is a Pro feature',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description ??
                  'Upgrade your plan to unlock $featureName and get higher daily/weekly usage limits.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('View Plans'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlansScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
