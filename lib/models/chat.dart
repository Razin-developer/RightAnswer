class Chat {
  final String id;
  final String name;
  final String? subjectId;
  final String? subjectName;
  final List<String> chapterIds;
  final List<String> chapterNames;
  final bool isTemporary;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Chat({
    required this.id,
    required this.name,
    this.subjectId,
    this.subjectName,
    required this.chapterIds,
    required this.chapterNames,
    required this.isTemporary,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'chapterIds': chapterIds.join('||'),
    'chapterNames': chapterNames.join('||'),
    'isTemporary': isTemporary ? 1 : 0,
    'isPinned': isPinned ? 1 : 0,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Chat.fromMap(Map<String, dynamic> m) => Chat(
    id: m['id'] as String,
    name: m['name'] as String,
    subjectId: m['subjectId'] as String?,
    subjectName: m['subjectName'] as String?,
    chapterIds: _split(m['chapterIds'] as String?),
    chapterNames: _split(m['chapterNames'] as String?),
    isTemporary: (m['isTemporary'] as int? ?? 0) == 1,
    isPinned: (m['isPinned'] as int? ?? 0) == 1,
    createdAt: DateTime.parse(m['createdAt'] as String),
    updatedAt: DateTime.parse(m['updatedAt'] as String),
  );

  static List<String> _split(String? s) =>
      (s == null || s.isEmpty) ? [] : s.split('||').where((x) => x.isNotEmpty).toList();

  Chat copyWith({
    String? name,
    String? subjectId,
    String? subjectName,
    List<String>? chapterIds,
    List<String>? chapterNames,
    bool? isPinned,
    DateTime? updatedAt,
  }) =>
      Chat(
        id: id,
        name: name ?? this.name,
        subjectId: subjectId ?? this.subjectId,
        subjectName: subjectName ?? this.subjectName,
        chapterIds: chapterIds ?? this.chapterIds,
        chapterNames: chapterNames ?? this.chapterNames,
        isTemporary: isTemporary,
        isPinned: isPinned ?? this.isPinned,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
