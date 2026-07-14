class Chapter {
  final String id;
  final String subjectId;
  final String title;
  final String className;
  final String rawContent;
  final DateTime createdAt;

  Chapter({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.className,
    this.rawContent = '',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'className': className,
    'rawContent': rawContent,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
    id: map['id'] as String,
    subjectId: map['subjectId'] as String,
    title: map['title'] as String,
    className: map['className'] as String,
    rawContent: (map['rawContent'] as String?) ?? '',
    createdAt: DateTime.parse(map['createdAt'] as String),
  );

  Chapter copyWith({String? title, String? className, String? rawContent}) => Chapter(
    id: id,
    subjectId: subjectId,
    title: title ?? this.title,
    className: className ?? this.className,
    rawContent: rawContent ?? this.rawContent,
    createdAt: createdAt,
  );
}
