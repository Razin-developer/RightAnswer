class QueuedRequest {
  final String id;
  final String chapterId;
  final String subjectId;
  final String toolType;
  final String? question;
  final String language;
  final String gradeLevel;
  final String tone;
  final String outputLength;
  /// pending | processing | done | failed
  final String status;
  final String? errorMessage;
  final DateTime createdAt;
  // Denormalized for display
  final String? chapterTitle;
  final String? subjectName;

  QueuedRequest({
    required this.id,
    required this.chapterId,
    required this.subjectId,
    required this.toolType,
    this.question,
    required this.language,
    required this.gradeLevel,
    required this.tone,
    required this.outputLength,
    required this.status,
    this.errorMessage,
    required this.createdAt,
    this.chapterTitle,
    this.subjectName,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'chapterId': chapterId,
        'subjectId': subjectId,
        'toolType': toolType,
        'question': question,
        'language': language,
        'gradeLevel': gradeLevel,
        'tone': tone,
        'outputLength': outputLength,
        'status': status,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
      };

  factory QueuedRequest.fromMap(Map<String, dynamic> m) => QueuedRequest(
        id: m['id'] as String,
        chapterId: m['chapterId'] as String,
        subjectId: m['subjectId'] as String,
        toolType: m['toolType'] as String,
        question: m['question'] as String?,
        language: m['language'] as String,
        gradeLevel: m['gradeLevel'] as String,
        tone: m['tone'] as String,
        outputLength: m['outputLength'] as String,
        status: m['status'] as String,
        errorMessage: m['errorMessage'] as String?,
        createdAt: DateTime.parse(m['createdAt'] as String),
        chapterTitle: m['chapterTitle'] as String?,
        subjectName: m['subjectName'] as String?,
      );
}
