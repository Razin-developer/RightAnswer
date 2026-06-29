import 'dart:convert';

class SavedOutput {
  final String id;
  final String subjectId;
  final String chapterId;
  final String toolType;
  final String? question;
  final String answer;
  final String language;
  final List<String> usedChunkIds;
  final DateTime createdAt;
  // Optional denormalized names for display
  final String? subjectName;
  final String? chapterTitle;

  SavedOutput({
    required this.id,
    required this.subjectId,
    required this.chapterId,
    required this.toolType,
    this.question,
    required this.answer,
    required this.language,
    required this.usedChunkIds,
    required this.createdAt,
    this.subjectName,
    this.chapterTitle,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subjectId': subjectId,
    'chapterId': chapterId,
    'toolType': toolType,
    'question': question,
    'answer': answer,
    'language': language,
    'usedChunkIds': jsonEncode(usedChunkIds),
    'createdAt': createdAt.toIso8601String(),
  };

  factory SavedOutput.fromMap(Map<String, dynamic> map) {
    final chunkIds = jsonDecode(map['usedChunkIds'] as String) as List;
    return SavedOutput(
      id: map['id'] as String,
      subjectId: map['subjectId'] as String,
      chapterId: map['chapterId'] as String,
      toolType: map['toolType'] as String,
      question: map['question'] as String?,
      answer: map['answer'] as String,
      language: map['language'] as String,
      usedChunkIds: chunkIds.cast<String>(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      subjectName: map['subjectName'] as String?,
      chapterTitle: map['chapterTitle'] as String?,
    );
  }
}
