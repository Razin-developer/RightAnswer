import 'dart:convert';

class StudyPlan {
  final String id;
  final String name;
  final String? subjectId;
  final String? subjectName;
  final List<String> chapterIds;
  final List<String> chapterNames;
  final DateTime examDate;
  final DateTime startDate;
  final List<int> freeDays; // DateTime weekday values: 1=Mon … 7=Sun
  final double hoursPerDay;
  final String status; // 'active' | 'paused' | 'completed'
  final int? reminderHour;
  final int? reminderMinute;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StudyPlan({
    required this.id,
    required this.name,
    this.subjectId,
    this.subjectName,
    this.chapterIds = const [],
    this.chapterNames = const [],
    required this.examDate,
    required this.startDate,
    this.freeDays = const [],
    this.hoursPerDay = 2.0,
    this.status = 'active',
    this.reminderHour,
    this.reminderMinute,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isActive => status == 'active';
  bool get isCompleted => status == 'completed';
  bool get isPaused => status == 'paused';
  bool get hasReminder => reminderHour != null && reminderMinute != null;

  int get daysToExam {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final e = DateTime(examDate.year, examDate.month, examDate.day);
    return e.difference(t).inDays;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'chapterIds': jsonEncode(chapterIds),
    'chapterNames': jsonEncode(chapterNames),
    'examDate': examDate.toIso8601String(),
    'startDate': startDate.toIso8601String(),
    'freeDays': jsonEncode(freeDays),
    'hoursPerDay': hoursPerDay,
    'status': status,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static StudyPlan fromMap(Map<String, dynamic> m) => StudyPlan(
    id: m['id'] as String,
    name: m['name'] as String,
    subjectId: m['subjectId'] as String?,
    subjectName: m['subjectName'] as String?,
    chapterIds: List<String>.from(
        (jsonDecode(m['chapterIds'] as String? ?? '[]') as List)),
    chapterNames: List<String>.from(
        (jsonDecode(m['chapterNames'] as String? ?? '[]') as List)),
    examDate: DateTime.parse(m['examDate'] as String),
    startDate: DateTime.parse(m['startDate'] as String),
    freeDays: List<int>.from(
        (jsonDecode(m['freeDays'] as String? ?? '[]') as List)),
    hoursPerDay: (m['hoursPerDay'] as num).toDouble(),
    status: m['status'] as String? ?? 'active',
    reminderHour: m['reminderHour'] as int?,
    reminderMinute: m['reminderMinute'] as int?,
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
  );

  StudyPlan copyWith({
    String? id,
    String? name,
    String? subjectId,
    String? subjectName,
    List<String>? chapterIds,
    List<String>? chapterNames,
    DateTime? examDate,
    DateTime? startDate,
    List<int>? freeDays,
    double? hoursPerDay,
    String? status,
    int? reminderHour,
    int? reminderMinute,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      StudyPlan(
        id: id ?? this.id,
        name: name ?? this.name,
        subjectId: subjectId ?? this.subjectId,
        subjectName: subjectName ?? this.subjectName,
        chapterIds: chapterIds ?? this.chapterIds,
        chapterNames: chapterNames ?? this.chapterNames,
        examDate: examDate ?? this.examDate,
        startDate: startDate ?? this.startDate,
        freeDays: freeDays ?? this.freeDays,
        hoursPerDay: hoursPerDay ?? this.hoursPerDay,
        status: status ?? this.status,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
