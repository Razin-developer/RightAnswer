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

  Future<void> insertAll(List<ExamQuestion> questions) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final q in questions) {
      batch.insert('exam_questions', q.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> update(ExamQuestion q) async {
    final db = await _db.database;
    await db.update('exam_questions', q.toMap(), where: 'id = ?', whereArgs: [q.id]);
  }

  Future<void> updateUserAnswer(String id, String? answer) async {
    final db = await _db.database;
    await db.update('exam_questions', {'userAnswer': answer}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByExam(String examId) async {
    final db = await _db.database;
    await db.delete('exam_questions', where: 'examId = ?', whereArgs: [examId]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('exam_questions', where: 'id = ?', whereArgs: [id]);
  }
}
