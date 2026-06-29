class Chapter {
  final String id;
  final String subjectId;
  final String title;
  final String className;
  final DateTime createdAt;

  Chapter({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.className,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'className': className,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
    id: map['id'] as String,
    subjectId: map['subjectId'] as String,
    title: map['title'] as String,
    className: map['className'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
