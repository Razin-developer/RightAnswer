import '../database/database_helper.dart';
import '../models/exam.dart';

class ExamRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Exam>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('exams', orderBy: 'updatedAt DESC');
    return rows.map(Exam.fromMap).toList();
  }

  Future<Exam?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query('exams', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Exam.fromMap(rows.first);
  }

  Future<void> insert(Exam exam) async {
    final db = await _db.database;
    await db.insert('exams', exam.toMap());
  }

  Future<void> update(Exam exam) async {
    final db = await _db.database;
    await db.update('exams', exam.toMap(), where: 'id = ?', whereArgs: [exam.id]);
  }

  Future<void> updateName(String id, String name) async {
    final db = await _db.database;
    await db.update(
      'exams',
      {'name': name, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchUpdatedAt(String id) async {
    final db = await _db.database;
    await db.update(
      'exams',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('exams', where: 'id = ?', whereArgs: [id]);
  }
}
