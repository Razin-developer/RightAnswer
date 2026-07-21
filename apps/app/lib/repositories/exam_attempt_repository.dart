import '../database/database_helper.dart';
import '../models/exam_attempt.dart';

class ExamAttemptRepository {
  final _db = DatabaseHelper.instance;

  Future<int> countByExam(String examId) async {
    final db = await _db.database;
    final rows = await db.query(
      'exam_attempts',
      columns: ['id'],
      where: 'examId = ? AND completedAt IS NOT NULL',
      whereArgs: [examId],
    );
    return rows.length;
  }

  Future<void> insert(ExamAttempt attempt) async {
    final db = await _db.database;
    await db.insert('exam_attempts', attempt.toMap());
  }

  Future<void> deleteByExam(String examId) async {
    final db = await _db.database;
    await db.delete('exam_attempts', where: 'examId = ?', whereArgs: [examId]);
  }
}
