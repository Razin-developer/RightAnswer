class Chapter {
  final String id;
  final String subjectId;
  final String title;
  final String className;
  final String rawContent;
  // Chapter number within its subject, as reported by the backend catalog
  // (GET /api/catalog). Defaults to 0 for chapters that predate this field
  // (e.g. imported archives) or weren't synced from the catalog.
  final int number;
  // Volume label from the backend catalog (e.g. "Part 1", "Part 2") for
  // subjects whose textbook is split into multiple physical books. Null for
  // subjects with a single textbook.
  final String? partLabel;
  final DateTime createdAt;

  Chapter({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.className,
    this.rawContent = '',
    this.number = 0,
    this.partLabel,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subjectId': subjectId,
    'title': title,
    'className': className,
    'rawContent': rawContent,
    'number': number,
    'partLabel': partLabel,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
    id: map['id'] as String,
    subjectId: map['subjectId'] as String,
    title: map['title'] as String,
    className: map['className'] as String,
    rawContent: (map['rawContent'] as String?) ?? '',
    number: (map['number'] as int?) ?? 0,
    partLabel: map['partLabel'] as String?,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );

  Chapter copyWith({
    String? title,
    String? className,
    String? rawContent,
    int? number,
    String? partLabel,
  }) => Chapter(
    id: id,
    subjectId: subjectId,
    title: title ?? this.title,
    className: className ?? this.className,
    rawContent: rawContent ?? this.rawContent,
    number: number ?? this.number,
    partLabel: partLabel ?? this.partLabel,
    createdAt: createdAt,
  );

  /// Display label used across pickers/chips, e.g. "Chapter 3: Force and Motion".
  String get displayLabel => number > 0 ? 'Chapter $number: $title' : title;
}
