import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_exception.dart';
import '../models/chat.dart';
import '../models/chat_message.dart';
import '../config/app_config.dart';
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

  Future<Map<String, dynamic>> _syncChatStrict(Chat chat) {
    return ApiService.instance.post('/api/chats', {
      'localId': chat.id,
      'name': chat.name,
      'subjectId': chat.subjectId,
      'subjectName': chat.subjectName,
      'chapterIds': chat.chapterIds,
      'chapterNames': chat.chapterNames,
      'isTemporary': chat.isTemporary,
      'isPinned': chat.isPinned,
    });
  }

  Future<void> updateChat(String localId, Map<String, dynamic> fields) async {
    if (!_ready) return;
    try {
      await ApiService.instance.put('/api/chats/by-local/$localId', fields);
    } catch (_) {}
  }

  Future<void> _syncMessageStrict(String chatLocalId, ChatMessage msg) async {
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
  }

  // ── Chat sharing ──────────────────────────────────────────────────────────

  /// Creates a 10-minute share link for a chat. Returns { url, expiresAt }.
  Future<Map<String, dynamic>> shareChatLink(String chatLocalId) async {
    if (!AuthService.instance.isLoggedIn) {
      throw AppException.authentication('Sign in to share chats.');
    }
    if (!ConnectivityService.instance.isOnline) {
      throw AppException.network('Connect to the internet to share chats.');
    }

    final chat = await _chatRepo.getById(chatLocalId);
    if (chat == null) {
      throw AppException.service('This chat could not be found locally.');
    }

    await _syncChatStrict(chat);
    final messages = await _messageRepo.getByChatId(chatLocalId);
    for (final message in messages) {
      await _syncMessageStrict(chatLocalId, message);
    }

    return ApiService.instance.post('/api/chats/by-local/$chatLocalId/share', {
      'accessLevel': 'full',
    });
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

  /// Downloads ZIP bytes from a share token, share page URL, or API URL.
  Future<List<int>> downloadContentZip(String urlOrToken) =>
      ApiService.instance.downloadBytes(_buildContentDownloadUrl(urlOrToken));

  String _buildContentDownloadUrl(String raw) {
    final token = _extractShareToken(raw);
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    if (uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      return '${uri.scheme}://${uri.authority}/api/share/$token';
    }

    final base = AppConfig.appUrl.trim().isNotEmpty
        ? AppConfig.appUrl.trim()
        : AppConfig.apiUrl.trim();
    if (base.isEmpty) {
      throw AppException.configuration('Missing APP_URL or API_URL.');
    }
    return '${base.replaceFirst(RegExp(r'/$'), '')}/api/share/$token';
  }

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
