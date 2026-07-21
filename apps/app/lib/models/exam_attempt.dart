import 'dart:convert';

class ExamAttempt {
  final String id;
  final String examId;
  final DateTime startedAt;
  final DateTime? completedAt;
  final Map<String, String> answers; // questionId → answer string
  final double score;
  final double totalMarks;
  final bool isPassed;

  const ExamAttempt({
    required this.id,
    required this.examId,
    required this.startedAt,
    this.completedAt,
    this.answers = const {},
    this.score = 0,
    this.totalMarks = 0,
    this.isPassed = false,
  });

  double get percentage => totalMarks > 0 ? (score / totalMarks) * 100 : 0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'examId': examId,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'answers': jsonEncode(answers),
    'score': score,
    'totalMarks': totalMarks,
    'isPassed': isPassed ? 1 : 0,
  };

  factory ExamAttempt.fromMap(Map<String, dynamic> m) => ExamAttempt(
    id: m['id'] as String,
    examId: m['examId'] as String,
    startedAt: DateTime.parse(m['startedAt'] as String),
    completedAt: m['completedAt'] != null
        ? DateTime.parse(m['completedAt'] as String)
        : null,
    answers: m['answers'] != null
        ? Map<String, String>.from(jsonDecode(m['answers'] as String) as Map)
        : {},
    score: (m['score'] as num?)?.toDouble() ?? 0,
    totalMarks: (m['totalMarks'] as num?)?.toDouble() ?? 0,
    isPassed: (m['isPassed'] as int?) == 1,
  );
}
