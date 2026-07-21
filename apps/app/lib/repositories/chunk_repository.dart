import '../database/database_helper.dart';
import '../models/chunk.dart';

class ChunkRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Chunk>> getByChapter(String chapterId) async {
    final db = await _db.database;
    final rows = await db.query('chunks',
        where: 'chapterId = ?', whereArgs: [chapterId], orderBy: 'chunkIndex ASC');
    return rows.map(Chunk.fromMap).toList();
  }

  Future<Map<String, int>> countsByChapters(List<String> chapterIds) async {
    if (chapterIds.isEmpty) return {};
    final db = await _db.database;
    final placeholders = List.filled(chapterIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT chapterId, COUNT(*) as c FROM chunks WHERE chapterId IN ($placeholders) GROUP BY chapterId',
      chapterIds,
    );
    return {for (final r in rows) r['chapterId'] as String: (r['c'] as int?) ?? 0};
  }

  Future<void> insertAll(List<Chunk> chunks) async {
    final db = await _db.database;
    final batch = db.batch();
    for (final c in chunks) {
      batch.insert('chunks', c.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteByChapter(String chapterId) async {
    final db = await _db.database;
    await db.delete('chunks', where: 'chapterId = ?', whereArgs: [chapterId]);
  }

  Future<void> updateEmbedding(String chunkId, String embeddingJson) async {
    final db = await _db.database;
    await db.update('chunks', {'embeddingJson': embeddingJson},
        where: 'id = ?', whereArgs: [chunkId]);
  }
}
