import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/chat.dart';

class ChatRepository {
  final _db = DatabaseHelper.instance;

  Future<void> insert(Chat chat) async {
    final db = await _db.database;
    await db.insert('chats', chat.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> update(Chat chat) async {
    final db = await _db.database;
    await db.update('chats', chat.toMap(), where: 'id = ?', whereArgs: [chat.id]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    // cascade delete messages
    await db.delete('chat_messages', where: 'chatId = ?', whereArgs: [id]);
    await db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  Future<Chat?> getById(String id) async {
    final db = await _db.database;
    final rows = await db.query('chats', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Chat.fromMap(rows.first);
  }

  Future<List<Chat>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('chats', orderBy: 'updatedAt DESC');
    return rows.map(Chat.fromMap).toList();
  }

  Future<void> updateName(String id, String name) async {
    final db = await _db.database;
    await db.update(
      'chats',
      {'name': name, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> touchUpdatedAt(String id) async {
    final db = await _db.database;
    await db.update(
      'chats',
      {'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Persists the subject/chapter classification the AI backend returned
  /// for this chat's latest answer (server-driven — the client no longer
  /// picks a subject/chapter up front).
  Future<void> updateClassification(
    String id, {
    String? subjectId,
    String? subjectName,
    String? chapterId,
    String? chapterName,
  }) async {
    final db = await _db.database;
    await db.update(
      'chats',
      {
        'subjectId': subjectId,
        'subjectName': subjectName,
        'chapterIds': chapterId == null ? '' : chapterId,
        'chapterNames': chapterName == null ? '' : chapterName,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> togglePin(String id, bool pinned) async {
    final db = await _db.database;
    await db.update(
      'chats',
      {'isPinned': pinned ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
