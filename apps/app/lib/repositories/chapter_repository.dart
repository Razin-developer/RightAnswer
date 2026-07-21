import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/chapter.dart';

class ChapterRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Chapter>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('chapters', orderBy: 'number ASC, createdAt ASC');
    return rows.map(Chapter.fromMap).toList();
  }

  Future<List<Chapter>> getBySubject(String subjectId) async {
    final db = await _db.database;
    final rows = await db.query('chapters',
        where: 'subjectId = ?',
        whereArgs: [subjectId],
        orderBy: 'number ASC, createdAt ASC');
    return rows.map(Chapter.fromMap).toList();
  }

  Future<Chapter?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query('chapters', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Chapter.fromMap(rows.first);
  }

  Future<void> insert(Chapter chapter) async {
    final db = await _db.database;
    await db.insert('chapters', chapter.toMap());
  }

  /// Insert-or-replace a batch of chapters in one transaction. Used by the
  /// background catalog sync (GET /api/catalog) to mirror the server's
  /// chapter list locally — chapters may be renamed/renumbered over time, so
  /// this replaces existing rows with matching ids rather than skipping them.
  Future<void> upsertAll(List<Chapter> chapters) async {
    if (chapters.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final chapter in chapters) {
      batch.insert(
        'chapters',
        chapter.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateRawContent(String id, String rawContent) async {
    final db = await _db.database;
    await db.update(
      'chapters',
      {'rawContent': rawContent},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('chapters', where: 'id = ?', whereArgs: [id]);
  }
}
