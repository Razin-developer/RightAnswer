import '../database/database_helper.dart';
import '../models/queued_request.dart';

class QueueRepository {
  final _db = DatabaseHelper.instance;

  Future<void> insert(QueuedRequest req) async {
    final db = await _db.database;
    await db.insert('request_queue', req.toMap());
  }

  Future<List<QueuedRequest>> getAll() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT q.*, c.title as chapterTitle, s.name as subjectName
      FROM request_queue q
      LEFT JOIN chapters c ON q.chapterId = c.id
      LEFT JOIN subjects s ON q.subjectId = s.id
      ORDER BY q.createdAt DESC
    ''');
    return rows.map(QueuedRequest.fromMap).toList();
  }

  Future<List<QueuedRequest>> getPending() async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT q.*, c.title as chapterTitle, s.name as subjectName
      FROM request_queue q
      LEFT JOIN chapters c ON q.chapterId = c.id
      LEFT JOIN subjects s ON q.subjectId = s.id
      WHERE q.status = 'pending'
      ORDER BY q.createdAt ASC
    ''');
    return rows.map(QueuedRequest.fromMap).toList();
  }

  Future<int> countByStatus(String status) async {
    final db = await _db.database;
    final res = await db.rawQuery(
        'SELECT COUNT(*) as c FROM request_queue WHERE status = ?', [status]);
    return (res.first['c'] as int?) ?? 0;
  }

  Future<int> countPending() => countByStatus('pending');

  Future<void> updateStatus(String id, String status, {String? error}) async {
    final db = await _db.database;
    final data = <String, dynamic>{'status': status};
    if (error != null) data['errorMessage'] = error;
    await db.update('request_queue', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> resetStuck() async {
    // Items stuck in 'processing' (e.g. app killed mid-task) → reset to pending
    final db = await _db.database;
    await db.update(
      'request_queue',
      {'status': 'pending'},
      where: 'status = ?',
      whereArgs: ['processing'],
    );
  }

  Future<void> retry(String id) async {
    final db = await _db.database;
    await db.update(
      'request_queue',
      {'status': 'pending', 'errorMessage': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('request_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearDone() async {
    final db = await _db.database;
    await db.delete('request_queue', where: 'status = ?', whereArgs: ['done']);
  }
}
