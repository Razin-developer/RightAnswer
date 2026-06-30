class Exam {
  final String id;
  final String name;
  final String type;
  final String? subjectId;
  final String? subjectName;
  final List<String> chapterIds;
  final List<String> chapterNames;
  final int questionCount;
  final int? timeLimit; // minutes, null = no limit
  final String difficulty; // 'easy' | 'medium' | 'hard' | 'mixed'
  final int mcqOptionCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Exam({
    required this.id,
    required this.name,
    required this.type,
    this.subjectId,
    this.subjectName,
    this.chapterIds = const [],
    this.chapterNames = const [],
    required this.questionCount,
    this.timeLimit,
    this.difficulty = 'medium',
    this.mcqOptionCount = 4,
    required this.createdAt,
    required this.updatedAt,
  });

  static List<String> _split(String? s) =>
      (s == null || s.isEmpty) ? [] : s.split('||').where((x) => x.isNotEmpty).toList();

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'chapterIds': chapterIds.join('||'),
    'chapterNames': chapterNames.join('||'),
    'questionCount': questionCount,
    'timeLimit': timeLimit,
    'difficulty': difficulty,
    'mcqOptionCount': mcqOptionCount,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Exam.fromMap(Map<String, dynamic> m) => Exam(
    id: m['id'] as String,
    name: m['name'] as String,
    type: m['type'] as String,
    subjectId: m['subjectId'] as String?,
    subjectName: m['subjectName'] as String?,
    chapterIds: _split(m['chapterIds'] as String?),
    chapterNames: _split(m['chapterNames'] as String?),
    questionCount: (m['questionCount'] as int?) ?? 0,
    timeLimit: m['timeLimit'] as int?,
    difficulty: (m['difficulty'] as String?) ?? 'medium',
    mcqOptionCount: (m['mcqOptionCount'] as int?) ?? 4,
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
  );

  Exam copyWith({
    String? name,
    String? type,
    String? subjectId,
    String? subjectName,
    List<String>? chapterIds,
    List<String>? chapterNames,
    int? questionCount,
    int? timeLimit,
    String? difficulty,
    int? mcqOptionCount,
    DateTime? updatedAt,
  }) => Exam(
    id: id,
    name: name ?? this.name,
    type: type ?? this.type,
    subjectId: subjectId ?? this.subjectId,
    subjectName: subjectName ?? this.subjectName,
    chapterIds: chapterIds ?? this.chapterIds,
    chapterNames: chapterNames ?? this.chapterNames,
    questionCount: questionCount ?? this.questionCount,
    timeLimit: timeLimit ?? this.timeLimit,
    difficulty: difficulty ?? this.difficulty,
    mcqOptionCount: mcqOptionCount ?? this.mcqOptionCount,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
