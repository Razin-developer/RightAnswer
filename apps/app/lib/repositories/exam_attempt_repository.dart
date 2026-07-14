import '../database/database_helper.dart';
import '../models/exam_attempt.dart';

class ExamAttemptRepository {
  final _db = DatabaseHelper.instance;

  Future<List<ExamAttempt>> getByExam(String examId) async {
    final db = await _db.database;
    final rows = await db.query(
      'exam_attempts',
      where: 'examId = ?',
      whereArgs: [examId],
      orderBy: 'startedAt DESC',
    );
    return rows.map(ExamAttempt.fromMap).toList();
  }

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

  Future<ExamAttempt?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query(
      'exam_attempts',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return ExamAttempt.fromMap(rows.first);
  }

  Future<void> insert(ExamAttempt attempt) async {
    final db = await _db.database;
    await db.insert('exam_attempts', attempt.toMap());
  }

  Future<void> update(ExamAttempt attempt) async {
    final db = await _db.database;
    await db.update(
      'exam_attempts',
      attempt.toMap(),
      where: 'id = ?',
      whereArgs: [attempt.id],
    );
  }

  Future<void> deleteByExam(String examId) async {
    final db = await _db.database;
    await db.delete('exam_attempts', where: 'examId = ?', whereArgs: [examId]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('exam_attempts', where: 'id = ?', whereArgs: [id]);
  }
}
