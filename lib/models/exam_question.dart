import 'dart:convert';

class ExamQuestion {
  final String id;
  final String examId;
  final int questionIndex;
  final String type; // 'mcq' | 'true_false' | 'fill_blank' | 'short_answer' | 'long_answer'
  final String question;
  final List<String>? options; // MCQ options or ['True','False'] for TF
  final String correctAnswer;
  final String? explanation;
  String? userAnswer; // mutable for practice mode

  ExamQuestion({
    required this.id,
    required this.examId,
    required this.questionIndex,
    required this.type,
    required this.question,
    this.options,
    required this.correctAnswer,
    this.explanation,
    this.userAnswer,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'examId': examId,
    'questionIndex': questionIndex,
    'type': type,
    'question': question,
    'options': options != null ? jsonEncode(options) : null,
    'correctAnswer': correctAnswer,
    'explanation': explanation,
    'userAnswer': userAnswer,
  };

  factory ExamQuestion.fromMap(Map<String, dynamic> m) => ExamQuestion(
    id: m['id'] as String,
    examId: m['examId'] as String,
    questionIndex: m['questionIndex'] as int,
    type: m['type'] as String,
    question: m['question'] as String,
    options: m['options'] != null
        ? (jsonDecode(m['options'] as String) as List).cast<String>()
        : null,
    correctAnswer: m['correctAnswer'] as String,
    explanation: m['explanation'] as String?,
    userAnswer: m['userAnswer'] as String?,
  );

  ExamQuestion copyWith({
    String? question,
    List<String>? options,
    String? correctAnswer,
    String? explanation,
    String? userAnswer,
  }) => ExamQuestion(
    id: id,
    examId: examId,
    questionIndex: questionIndex,
    type: type,
    question: question ?? this.question,
    options: options ?? this.options,
    correctAnswer: correctAnswer ?? this.correctAnswer,
    explanation: explanation ?? this.explanation,
    userAnswer: userAnswer ?? this.userAnswer,
  );
}
