import '../database/database_helper.dart';
import '../models/study_day.dart';

class StudyDayRepository {
  final _db = DatabaseHelper.instance;

  Future<List<StudyDay>> getByPlan(String planId) async {
    final db = await _db.database;
    final rows = await db.query(
      'study_days',
      where: 'planId = ?',
      whereArgs: [planId],
      orderBy: 'date ASC',
    );
    return rows.map(StudyDay.fromMap).toList();
  }

  Future<void> insert(StudyDay day) async {
    final db = await _db.database;
    await db.insert('study_days', day.toMap());
  }

  Future<void> update(StudyDay day) async {
    final db = await _db.database;
    await db.update('study_days', day.toMap(),
        where: 'id = ?', whereArgs: [day.id]);
  }

  Future<void> deleteByPlan(String planId) async {
    final db = await _db.database;
    await db.delete('study_days', where: 'planId = ?', whereArgs: [planId]);
  }
}
