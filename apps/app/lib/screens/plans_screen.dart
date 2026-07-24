import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/plans_service.dart';
import '../widgets/app_feedback.dart';
import 'payment_screen.dart';

const _coral = Color(0xFFCC785C);

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  bool _loading = true;
  List<PlanInfo> _plans = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final plans = await PlansService.listPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppFeedback.showErrorToast(context, 'Could not load plans. Check your connection.');
    }
  }

  void _upgrade(PlanInfo plan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(plan: plan.id, planLabel: plan.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentPlan = AuthService.instance.currentUser?.plan ?? 'hobby';

    return Scaffold(
      appBar: AppBar(title: const Text('Plans'), centerTitle: false),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 32,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 10),
                  const Text('Could not load plans'),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                Text(
                  'Choose the plan that fits how much you study',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                for (final plan in _plans) ...[
                  _PlanCard(
                    plan: plan,
                    isCurrent: plan.id == currentPlan,
                    onUpgrade: () => _upgrade(plan),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanInfo plan;
  final bool isCurrent;
  final VoidCallback onUpgrade;

  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.onUpgrade,
  });

  static const _icons = {
    'hobby': Icons.school_outlined,
    'pro': Icons.bolt_rounded,
    'scholar': Icons.auto_awesome_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFree = plan.priceInr == 0;
    final isScholar = plan.id == 'scholar';

    // Deliberately no dollar figures here — plan cards sell the tier, not
    // the accounting. Exact numbers live in usage_me/the settings usage
    // bar, scaled to a relative meter rather than spelled out.
    final creditLine = isFree
        ? 'Everyday AI credit to get you started'
        : isScholar
        ? 'Our highest AI credit — well beyond Pro'
        : 'More AI credit than Hobby, refreshed daily & weekly';
    final features = [
      creditLine,
      plan.studyPlans
          ? 'Exams & Study Plans unlocked'
          : 'Exams & Study Plans locked (upgrade to unlock)',
      if (isScholar) 'Everything in Pro, and then some',
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrent ? _coral : theme.dividerColor,
          width: isCurrent ? 1.6 : 1,
        ),
        boxShadow: isCurrent || isScholar
            ? [
                BoxShadow(
                  color: _coral.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _coral.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _icons[plan.id] ?? Icons.workspace_premium_outlined,
                  size: 18,
                  color: _coral,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                plan.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _coral.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Current Plan',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _coral,
                    ),
                  ),
                )
              else if (isScholar)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF15803D).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Best Value',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isFree ? 'Free' : '₹${plan.priceInr}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isFree ? null : _coral,
                ),
              ),
              if (!isFree) ...[
                const SizedBox(width: 4),
                Text(
                  '/ month',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (final feature in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(feature, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          if (!isFree) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: isCurrent
                  ? OutlinedButton(
                      onPressed: null,
                      child: const Text('Active'),
                    )
                  : FilledButton(
                      onPressed: onUpgrade,
                      child: Text('Upgrade to ${plan.name}'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
