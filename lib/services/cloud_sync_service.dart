import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat.dart';
import '../models/chat_message.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._();
  CloudSyncService._();

  bool get _ready =>
      AuthService.instance.isLoggedIn &&
      ConnectivityService.instance.isOnline;

  // ── Chats ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchChats() async {
    final data = await ApiService.instance.get('/api/chats');
    return (data['chats'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> syncChat(Chat chat) async {
    if (!_ready) return null;
    try {
      return await ApiService.instance.post('/api/chats', {
        'localId': chat.id,
        'name': chat.name,
        'subjectId': chat.subjectId,
        'subjectName': chat.subjectName,
        'chapterIds': chat.chapterIds,
        'chapterNames': chat.chapterNames,
        'isTemporary': chat.isTemporary,
        'isPinned': chat.isPinned,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> updateChat(String localId, Map<String, dynamic> fields) async {
    if (!_ready) return;
    try {
      await ApiService.instance.put('/api/chats/by-local/$localId', fields);
    } catch (_) {}
  }

  Future<void> deleteChat(String localId) async {
    if (!_ready) return;
    try {
      await ApiService.instance.delete('/api/chats/by-local/$localId');
    } catch (_) {}
  }

  Future<void> syncMessage(String chatLocalId, ChatMessage msg) async {
    if (!_ready) return;
    try {
      await ApiService.instance.post(
        '/api/chats/by-local/$chatLocalId/messages',
        {
          'localId': msg.id,
          'role': msg.role,
          'content': msg.content,
          'responseLanguage': msg.responseLanguage,
          'responseLength': msg.responseLength,
          'reasoningLevel': msg.reasoningLevel,
          'tokenCount': msg.tokenCount,
          'cost': msg.cost,
          'sourceChunks': msg.sourceChunks,
          'imagePath': msg.imagePath,
        },
      );
    } catch (_) {}
  }

  // ── Chat sharing ──────────────────────────────────────────────────────────

  /// Creates a 10-minute share link for a chat. Returns { url, expiresAt }.
  Future<Map<String, dynamic>> shareChatLink(String chatLocalId) {
    return ApiService.instance.post(
      '/api/chats/by-local/$chatLocalId/share',
      {},
    );
  }

  /// Joins a chat via share token. Returns joined chat data.
  Future<Map<String, dynamic>> joinChatViaToken(String token) {
    return ApiService.instance.get('/api/share/$token');
  }

  // ── Content ZIP sharing ───────────────────────────────────────────────────

  /// Uploads a ZIP to the server, returns { url, expiresAt }.
  Future<Map<String, dynamic>> uploadContentZip({
    required List<int> bytes,
    required Map<String, dynamic> metadata,
  }) async {
    final dir = await getTemporaryDirectory();
    final tmpFile = File(
      '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    await tmpFile.writeAsBytes(bytes);
    try {
      return await ApiService.instance.uploadFile(
        '/api/content',
        tmpFile,
        fields: {'metadata': jsonEncode(metadata)},
      );
    } finally {
      await tmpFile.delete().catchError((_) {});
    }
  }

  /// Downloads ZIP bytes from a share URL.
  Future<List<int>> downloadContentZip(String url) =>
      ApiService.instance.downloadBytes(url);
}
