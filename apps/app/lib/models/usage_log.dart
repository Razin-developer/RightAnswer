class UsageLog {
  final String id;
  final String toolType;
  final int inputTokensEstimate;
  final int outputTokensEstimate;
  final double estimatedCost;
  final DateTime createdAt;

  UsageLog({
    required this.id,
    required this.toolType,
    required this.inputTokensEstimate,
    required this.outputTokensEstimate,
    required this.estimatedCost,
    required this.createdAt,
  });

  int get totalTokens => inputTokensEstimate + outputTokensEstimate;

  Map<String, dynamic> toMap() => {
    'id': id,
    'toolType': toolType,
    'inputTokensEstimate': inputTokensEstimate,
    'outputTokensEstimate': outputTokensEstimate,
    'estimatedCost': estimatedCost,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UsageLog.fromMap(Map<String, dynamic> map) => UsageLog(
    id: map['id'] as String,
    toolType: map['toolType'] as String,
    inputTokensEstimate: map['inputTokensEstimate'] as int,
    outputTokensEstimate: map['outputTokensEstimate'] as int,
    estimatedCost: (map['estimatedCost'] as num).toDouble(),
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
