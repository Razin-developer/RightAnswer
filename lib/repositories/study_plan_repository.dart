import '../database/database_helper.dart';
import '../models/study_plan.dart';

class StudyPlanRepository {
  final _db = DatabaseHelper.instance;

  Future<List<StudyPlan>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('study_plans', orderBy: 'createdAt DESC');
    return rows.map(StudyPlan.fromMap).toList();
  }

  Future<StudyPlan?> getById(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('study_plans', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return StudyPlan.fromMap(rows.first);
  }

  Future<void> insert(StudyPlan plan) async {
    final db = await _db.database;
    await db.insert('study_plans', plan.toMap());
  }

  Future<void> update(StudyPlan plan) async {
    final db = await _db.database;
    await db.update('study_plans', plan.toMap(),
        where: 'id = ?', whereArgs: [plan.id]);
  }

  Future<void> updateStatus(String id, String status) async {
    final db = await _db.database;
    await db.update(
      'study_plans',
      {'status': status, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('study_plans', where: 'id = ?', whereArgs: [id]);
  }
}
