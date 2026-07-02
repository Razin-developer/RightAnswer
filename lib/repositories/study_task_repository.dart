import '../database/database_helper.dart';
import '../models/study_task.dart';

class StudyTaskRepository {
  final _db = DatabaseHelper.instance;

  Future<List<StudyTask>> getByDay(String dayId) async {
    final db = await _db.database;
    final rows = await db.query(
      'study_tasks',
      where: 'dayId = ?',
      whereArgs: [dayId],
      orderBy: 'sortOrder ASC',
    );
    return rows.map(StudyTask.fromMap).toList();
  }

  Future<List<StudyTask>> getByPlan(String planId) async {
    final db = await _db.database;
    final rows = await db.query(
      'study_tasks',
      where: 'planId = ?',
      whereArgs: [planId],
      orderBy: 'sortOrder ASC',
    );
    return rows.map(StudyTask.fromMap).toList();
  }

  Future<void> insert(StudyTask task) async {
    final db = await _db.database;
    await db.insert('study_tasks', task.toMap());
  }

  Future<void> update(StudyTask task) async {
    final db = await _db.database;
    await db.update('study_tasks', task.toMap(),
        where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> deleteByPlan(String planId) async {
    final db = await _db.database;
    await db.delete('study_tasks', where: 'planId = ?', whereArgs: [planId]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('study_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countCompleted(String planId) async {
    final db = await _db.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM study_tasks WHERE planId = ? AND isCompleted = 1',
      [planId],
    );
    return r.isEmpty ? 0 : (r.first['cnt'] as int? ?? 0);
  }

  Future<int> countTotal(String planId) async {
    final db = await _db.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM study_tasks WHERE planId = ?',
      [planId],
    );
    return r.isEmpty ? 0 : (r.first['cnt'] as int? ?? 0);
  }
}
