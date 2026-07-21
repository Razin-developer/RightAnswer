class ExamMessage {
  final String id;
  final String examId;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? imagePath;
  final DateTime createdAt;

  const ExamMessage({
    required this.id,
    required this.examId,
    required this.role,
    required this.content,
    this.imagePath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'examId': examId,
    'role': role,
    'content': content,
    'imagePath': imagePath,
    'createdAt': createdAt.toIso8601String(),
  };

  factory ExamMessage.fromMap(Map<String, dynamic> m) => ExamMessage(
    id: m['id'] as String,
    examId: m['examId'] as String,
    role: m['role'] as String,
    content: m['content'] as String,
    imagePath: m['imagePath'] as String?,
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
