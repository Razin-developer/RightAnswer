class StudyDay {
  final String id;
  final String planId;
  final DateTime date;
  final bool isCompleted;

  const StudyDay({
    required this.id,
    required this.planId,
    required this.date,
    this.isCompleted = false,
  });

  bool get isToday {
    final n = DateTime.now();
    return date.year == n.year && date.month == n.month && date.day == n.day;
  }

  bool get isPast {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(date.year, date.month, date.day);
    return d.isBefore(today);
  }

  bool get isFuture {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(date.year, date.month, date.day);
    return d.isAfter(today);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'planId': planId,
    'date': date.toIso8601String(),
    'isCompleted': isCompleted ? 1 : 0,
  };

  static StudyDay fromMap(Map<String, dynamic> m) => StudyDay(
    id: m['id'] as String,
    planId: m['planId'] as String,
    date: DateTime.parse(m['date'] as String),
    isCompleted: (m['isCompleted'] as int?) == 1,
  );

  StudyDay copyWith({
    String? id,
    String? planId,
    DateTime? date,
    bool? isCompleted,
  }) =>
      StudyDay(
        id: id ?? this.id,
        planId: planId ?? this.planId,
        date: date ?? this.date,
        isCompleted: isCompleted ?? this.isCompleted,
      );
}
