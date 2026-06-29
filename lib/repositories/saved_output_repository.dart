import '../database/database_helper.dart';
import '../models/saved_output.dart';

class SavedOutputRepository {
  final _db = DatabaseHelper.instance;

  Future<List<SavedOutput>> getAll({String? subjectId, String? chapterId, String? toolType}) async {
    final db = await _db.database;
    final conditions = <String>[];
    final args = <dynamic>[];

    // Join with subjects and chapters to get names
    String query = '''
      SELECT so.*, s.name as subjectName, c.title as chapterTitle
      FROM saved_outputs so
      LEFT JOIN subjects s ON so.subjectId = s.id
      LEFT JOIN chapters c ON so.chapterId = c.id
    ''';

    if (subjectId != null) { conditions.add('so.subjectId = ?'); args.add(subjectId); }
    if (chapterId != null) { conditions.add('so.chapterId = ?'); args.add(chapterId); }
    if (toolType != null) { conditions.add('so.toolType = ?'); args.add(toolType); }

    if (conditions.isNotEmpty) {
      query += ' WHERE ${conditions.join(' AND ')}';
    }
    query += ' ORDER BY so.createdAt DESC';

    final rows = await db.rawQuery(query, args);
    return rows.map(SavedOutput.fromMap).toList();
  }

  Future<void> insert(SavedOutput output) async {
    final db = await _db.database;
    await db.insert('saved_outputs', output.toMap());
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('saved_outputs', where: 'id = ?', whereArgs: [id]);
  }
}
