import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_exception.dart';
import '../models/chat.dart';
import '../models/chat_message.dart';
import '../repositories/chat_message_repository.dart';
import '../repositories/chat_repository.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

class JoinedChatResult {
  final String localChatId;
  final String remoteChatId;
  final String name;
  final int messageCount;

  const JoinedChatResult({
    required this.localChatId,
    required this.remoteChatId,
    required this.name,
    required this.messageCount,
  });
}

class CloudSyncService {
  static final CloudSyncService instance = CloudSyncService._();
  CloudSyncService._();

  final _chatRepo = ChatRepository();
  final _messageRepo = ChatMessageRepository();

  bool get _ready =>
      AuthService.instance.isLoggedIn && ConnectivityService.instance.isOnline;

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
      await ApiService.instance
          .post('/api/chats/by-local/$chatLocalId/messages', {
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
          });
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

  Future<JoinedChatResult> joinChatFromShareToken(String tokenOrUrl) async {
    final token = _extractShareToken(tokenOrUrl);
    final data = await joinChatViaToken(token);
    final chatJson = data['chat'] as Map<String, dynamic>?;
    if (chatJson == null) {
      throw AppException.service('This shared chat could not be loaded.');
    }

    final remoteChatId =
        (chatJson['id'] as String?) ?? (chatJson['_id'] as String?) ?? '';
    if (remoteChatId.isEmpty) {
      throw AppException.service('Shared chat data is incomplete.');
    }

    final localChatId =
        (chatJson['localId'] as String?)?.trim().isNotEmpty == true
        ? (chatJson['localId'] as String).trim()
        : const Uuid().v4();

    final createdAt = DateTime.tryParse(chatJson['createdAt'] as String? ?? '');
    final updatedAt = DateTime.tryParse(chatJson['updatedAt'] as String? ?? '');
    final chat = Chat(
      id: localChatId,
      name: (chatJson['name'] as String?)?.trim().isNotEmpty == true
          ? (chatJson['name'] as String).trim()
          : 'Shared Chat',
      subjectId: chatJson['subjectId'] as String?,
      subjectName: chatJson['subjectName'] as String?,
      chapterIds: List<String>.from(
        (chatJson['chapterIds'] as List?) ?? const [],
      ),
      chapterNames: List<String>.from(
        (chatJson['chapterNames'] as List?) ?? const [],
      ),
      isTemporary: (chatJson['isTemporary'] as bool?) ?? false,
      isPinned: (chatJson['isPinned'] as bool?) ?? false,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
    await _chatRepo.insert(chat);

    final messagePayload = await ApiService.instance.get(
      '/api/chats/$remoteChatId/messages',
    );
    final rawMessages =
        (messagePayload['messages'] as List?) ?? const <dynamic>[];

    await _messageRepo.deleteByChatId(localChatId);
    for (final item in rawMessages) {
      final messageJson = item as Map<String, dynamic>;
      final createdAt = DateTime.tryParse(
        messageJson['createdAt'] as String? ?? '',
      );
      final sourceChunks = messageJson['sourceChunks'];
      await _messageRepo.insert(
        ChatMessage(
          id:
              (messageJson['localId'] as String?) ??
              (messageJson['_id'] as String?) ??
              const Uuid().v4(),
          chatId: localChatId,
          role: (messageJson['role'] as String?) ?? 'assistant',
          content: (messageJson['content'] as String?) ?? '',
          imagePath: messageJson['imagePath'] as String?,
          responseLanguage: messageJson['responseLanguage'] as String?,
          responseLength:
              (messageJson['responseLength'] as String?) ?? 'normal',
          reasoningLevel: (messageJson['reasoningLevel'] as String?) ?? 'mid',
          tokenCount: (messageJson['tokenCount'] as int?) ?? 0,
          cost: ((messageJson['cost'] as num?)?.toDouble()) ?? 0,
          sourceChunks: sourceChunks is List
              ? List<String>.from(sourceChunks)
              : const <String>[],
          createdAt: createdAt ?? DateTime.now(),
        ),
      );
    }

    return JoinedChatResult(
      localChatId: localChatId,
      remoteChatId: remoteChatId,
      name: chat.name,
      messageCount: rawMessages.length,
    );
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
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Downloads ZIP bytes from a share URL.
  Future<List<int>> downloadContentZip(String url) =>
      ApiService.instance.downloadBytes(url);

  String _extractShareToken(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw AppException.validation('Share link is empty.');
    }

    if (!value.contains('://')) {
      return value.split('/').where((segment) => segment.isNotEmpty).last;
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      throw AppException.validation('Share link is invalid.');
    }

    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) {
      throw AppException.validation('Share link is invalid.');
    }
    return segments.last;
  }
}
