import '../database/database_helper.dart';
import '../models/subject.dart';

class SubjectRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Subject>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('subjects', orderBy: 'createdAt DESC');
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

  Future<void> update(Subject subject) async {
    final db = await _db.database;
    await db.update('subjects', subject.toMap(), where: 'id = ?', whereArgs: [subject.id]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('subjects', where: 'id = ?', whereArgs: [id]);
  }
}
