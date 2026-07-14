import '../database/database_helper.dart';
import '../models/exam_message.dart';

class ExamMessageRepository {
  final _db = DatabaseHelper.instance;

  Future<List<ExamMessage>> getByExam(String examId) async {
    final db = await _db.database;
    final rows = await db.query(
      'exam_messages',
      where: 'examId = ?',
      whereArgs: [examId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(ExamMessage.fromMap).toList();
  }

  Future<void> insert(ExamMessage msg) async {
    final db = await _db.database;
    await db.insert('exam_messages', msg.toMap());
  }

  Future<void> deleteByExam(String examId) async {
    final db = await _db.database;
    await db.delete('exam_messages', where: 'examId = ?', whereArgs: [examId]);
  }
}
