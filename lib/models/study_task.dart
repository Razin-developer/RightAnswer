class StudyTask {
  final String id;
  final String planId;
  final String dayId;
  final String title;
  final String? description;
  final String? chapterId;
  final String? chapterName;
  final int durationMinutes;
  final bool isCompleted;
  final DateTime? completedAt;
  final int sortOrder;

  const StudyTask({
    required this.id,
    required this.planId,
    required this.dayId,
    required this.title,
    this.description,
    this.chapterId,
    this.chapterName,
    this.durationMinutes = 30,
    this.isCompleted = false,
    this.completedAt,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'planId': planId,
    'dayId': dayId,
    'title': title,
    'description': description,
    'chapterId': chapterId,
    'chapterName': chapterName,
    'durationMinutes': durationMinutes,
    'isCompleted': isCompleted ? 1 : 0,
    'completedAt': completedAt?.toIso8601String(),
    'sortOrder': sortOrder,
  };

  static StudyTask fromMap(Map<String, dynamic> m) => StudyTask(
    id: m['id'] as String,
    planId: m['planId'] as String,
    dayId: m['dayId'] as String,
    title: m['title'] as String,
    description: m['description'] as String?,
    chapterId: m['chapterId'] as String?,
    chapterName: m['chapterName'] as String?,
    durationMinutes: (m['durationMinutes'] as int?) ?? 30,
    isCompleted: (m['isCompleted'] as int?) == 1,
    completedAt: m['completedAt'] != null
        ? DateTime.parse(m['completedAt'] as String)
        : null,
    sortOrder: (m['sortOrder'] as int?) ?? 0,
  );

  StudyTask copyWith({
    String? id,
    String? planId,
    String? dayId,
    String? title,
    String? description,
    String? chapterId,
    String? chapterName,
    int? durationMinutes,
    bool? isCompleted,
    DateTime? completedAt,
    int? sortOrder,
  }) =>
      StudyTask(
        id: id ?? this.id,
        planId: planId ?? this.planId,
        dayId: dayId ?? this.dayId,
        title: title ?? this.title,
        description: description ?? this.description,
        chapterId: chapterId ?? this.chapterId,
        chapterName: chapterName ?? this.chapterName,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        isCompleted: isCompleted ?? this.isCompleted,
        completedAt: completedAt ?? this.completedAt,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
