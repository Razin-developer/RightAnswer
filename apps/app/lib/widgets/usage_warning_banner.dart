import 'package:flutter/material.dart';

import '../screens/plans_screen.dart';
import '../services/auth_service.dart';
import '../services/plans_service.dart';

/// Dismissible warning bar shown once the signed-in user is close to their
/// plan's daily/weekly limit (server-computed threshold — see
/// PlansService.getUsage / routes::usage_me). Fetching usage is
/// best-effort: any failure here just means the banner stays hidden,
/// never a user-facing error, since it's a soft nudge, not core
/// functionality.
class UsageWarningBanner extends StatefulWidget {
  const UsageWarningBanner({super.key});

  @override
  State<UsageWarningBanner> createState() => _UsageWarningBannerState();
}

class _UsageWarningBannerState extends State<UsageWarningBanner> {
  UsageSnapshot? _usage;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthService.instance.isLoggedIn) return;
    try {
      final usage = await PlansService.getUsage();
      if (!mounted) return;
      setState(() => _usage = usage);
    } catch (_) {
      // Soft feature — never surface a failure for this.
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    if (_dismissed || usage == null || !usage.showWarning) {
      return const SizedBox.shrink();
    }

    return Material(
      color: const Color(0xFFFFF4E5),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "You've used ${usage.usagePercent.clamp(0, 100).toStringAsFixed(0)}% of your ${_planLabel(usage.plan)} plan's limit this period.",
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF7C2D12),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlansScreen()),
                ),
                child: const Text(
                  'Upgrade',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                color: const Color(0xFF7C2D12),
                onPressed: () => setState(() => _dismissed = true),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _planLabel(String plan) =>
      plan.isEmpty ? plan : plan[0].toUpperCase() + plan.substring(1);
}
