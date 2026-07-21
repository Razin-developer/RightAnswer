import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/chat_message.dart';

class ChatMessageRepository {
  final _db = DatabaseHelper.instance;

  Future<void> insert(ChatMessage msg) async {
    final db = await _db.database;
    await db.insert('chat_messages', msg.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByChatId(String chatId) async {
    final db = await _db.database;
    await db.delete('chat_messages', where: 'chatId = ?', whereArgs: [chatId]);
  }

  Future<List<ChatMessage>> getByChatId(String chatId) async {
    final db = await _db.database;
    final rows = await db.query(
      'chat_messages',
      where: 'chatId = ?',
      whereArgs: [chatId],
      orderBy: 'createdAt ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }
}
