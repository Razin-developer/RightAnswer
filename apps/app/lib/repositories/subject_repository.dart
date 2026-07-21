import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/subject.dart';

class SubjectRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Subject>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('subjects', orderBy: 'name ASC');
    return rows.map(Subject.fromMap).toList();
  }

  Future<Subject?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query('subjects', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Subject.fromMap(rows.first);
  }

  Future<void> insert(Subject subject) async {
    final db = await _db.database;
    await db.insert('subjects', subject.toMap());
  }

  /// Insert-or-replace a batch of subjects in one transaction. Used by the
  /// background catalog sync (GET /api/catalog) to mirror the server's
  /// subject list locally — subjects may be renamed/added over time, so this
  /// replaces existing rows with matching ids rather than skipping them.
  Future<void> upsertAll(List<Subject> subjects) async {
    if (subjects.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final subject in subjects) {
      batch.insert(
        'subjects',
        subject.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }
}
