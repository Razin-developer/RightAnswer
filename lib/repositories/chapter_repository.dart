import '../database/database_helper.dart';
import '../models/chapter.dart';

class ChapterRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Chapter>> getBySubject(String subjectId) async {
    final db = await _db.database;
    final rows = await db.query('chapters',
        where: 'subjectId = ?', whereArgs: [subjectId], orderBy: 'createdAt ASC');
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

  Future<void> update(Chapter chapter) async {
    final db = await _db.database;
    await db.update('chapters', chapter.toMap(), where: 'id = ?', whereArgs: [chapter.id]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('chapters', where: 'id = ?', whereArgs: [id]);
  }
}
