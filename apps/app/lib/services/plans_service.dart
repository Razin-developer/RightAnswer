import 'api_service.dart';

/// Usage snapshot for the signed-in user's current plan — mirrors
/// GET /api/usage/me. See routes::usage_me on the backend for how each
/// field is computed (daily question count, weekly credit spend).
class UsageSnapshot {
  final String plan;
  final int dailyQuestionsUsed;
  final int dailyQuestionLimit;
  final double weeklyCreditUsedUsd;
  final double weeklyCreditLimitUsd;
  final double creditBalanceUsd;
  final double usagePercent;
  final double warningThresholdPercent;
  final bool showWarning;

  const UsageSnapshot({
    required this.plan,
    required this.dailyQuestionsUsed,
    required this.dailyQuestionLimit,
    required this.weeklyCreditUsedUsd,
    required this.weeklyCreditLimitUsd,
    required this.creditBalanceUsd,
    required this.usagePercent,
    required this.warningThresholdPercent,
    required this.showWarning,
  });

  factory UsageSnapshot.fromJson(Map<String, dynamic> j) => UsageSnapshot(
    plan: j['plan'] as String? ?? 'hobby',
    dailyQuestionsUsed: (j['dailyQuestionsUsed'] as num?)?.toInt() ?? 0,
    dailyQuestionLimit: (j['dailyQuestionLimit'] as num?)?.toInt() ?? 0,
    weeklyCreditUsedUsd: (j['weeklyCreditUsedUsd'] as num?)?.toDouble() ?? 0,
    weeklyCreditLimitUsd: (j['weeklyCreditLimitUsd'] as num?)?.toDouble() ?? 0,
    creditBalanceUsd: (j['creditBalanceUsd'] as num?)?.toDouble() ?? 0,
    usagePercent: (j['usagePercent'] as num?)?.toDouble() ?? 0,
    warningThresholdPercent:
        (j['warningThresholdPercent'] as num?)?.toDouble() ?? 90,
    showWarning: j['showWarning'] as bool? ?? false,
  );
}

/// A plan purchase in progress/completed — mirrors the `payments` table.
class PlanPayment {
  final String id;
  final String plan;
  final int amountInr;
  final double creditsUsd;
  final String status;

  const PlanPayment({
    required this.id,
    required this.plan,
    required this.amountInr,
    required this.creditsUsd,
    required this.status,
  });

  factory PlanPayment.fromJson(Map<String, dynamic> j) => PlanPayment(
    id: j['id'] as String,
    plan: j['plan'] as String,
    amountInr: (j['amountInr'] as num).toInt(),
    creditsUsd: (j['creditsUsd'] as num).toDouble(),
    status: j['status'] as String,
  );
}

/// Public plan catalog entry — pricing/limits come straight from the
/// server's env-driven config, never hardcoded client-side, so the price
/// shown always matches what checkout actually charges.
class PlanInfo {
  final String id;
  final String name;
  final int priceInr;
  final double creditsUsd;
  final int dailyQuestionLimit;
  final double weeklyCreditUsd;
  final bool studyPlans;

  const PlanInfo({
    required this.id,
    required this.name,
    required this.priceInr,
    required this.creditsUsd,
    required this.dailyQuestionLimit,
    required this.weeklyCreditUsd,
    required this.studyPlans,
  });

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    priceInr: (j['priceInr'] as num).toInt(),
    creditsUsd: (j['creditsUsd'] as num).toDouble(),
    dailyQuestionLimit: (j['dailyQuestionLimit'] as num).toInt(),
    weeklyCreditUsd: (j['weeklyCreditUsd'] as num).toDouble(),
    studyPlans: j['studyPlans'] as bool? ?? false,
  );
}

class PlansService {
  PlansService._();

  static Future<List<PlanInfo>> listPlans() async {
    final data = await ApiService.instance.get('/api/plans');
    final raw = data['plans'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => PlanInfo.fromJson(m.map((k, v) => MapEntry(k.toString(), v))))
        .toList();
  }

  static Future<UsageSnapshot> getUsage() async {
    final data = await ApiService.instance.get('/api/usage/me');
    return UsageSnapshot.fromJson(data);
  }

  /// Starts a purchase for [plan] ("pro" or "scholar"). Returns the pending
  /// payment record (amount to charge, credits to be granted) for the mock
  /// payment screen to display before the user taps Success/Failure.
  static Future<PlanPayment> checkout(String plan) async {
    final data = await ApiService.instance.post('/api/plans/checkout', {
      'plan': plan,
    });
    return PlanPayment.fromJson(data['payment'] as Map<String, dynamic>);
  }

  /// Finalizes a payment — stands in for a real gateway's webhook. [status]
  /// must be "success" or "failed".
  static Future<PlanPayment> completePayment(
    String paymentId,
    String status,
  ) async {
    final data = await ApiService.instance.post(
      '/api/plans/payments/$paymentId/complete',
      {'status': status},
    );
    return PlanPayment.fromJson(data['payment'] as Map<String, dynamic>);
  }
}
