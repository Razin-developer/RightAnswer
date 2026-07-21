import '../database/database_helper.dart';
import '../models/exam_question.dart';

class ExamQuestionRepository {
  final _db = DatabaseHelper.instance;

  Future<List<ExamQuestion>> getByExam(String examId) async {
    final db = await _db.database;
    final rows = await db.query(
      'exam_questions',
      where: 'examId = ?',
      whereArgs: [examId],
      orderBy: 'questionIndex ASC',
    );
    return rows.map(ExamQuestion.fromMap).toList();
  }

  Future<void> insert(ExamQuestion q) async {
    final db = await _db.database;
    await db.insert('exam_questions', q.toMap());
  }

  Future<void> deleteByExam(String examId) async {
    final db = await _db.database;
    await db.delete('exam_questions', where: 'examId = ?', whereArgs: [examId]);
  }
}
