import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../constants/app_prompts.dart';
import '../models/app_exception.dart';
import '../models/chat_message.dart';
import '../models/usage_log.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import 'ai_backend_service.dart';
import 'retrieval_service.dart';

class ChatAIStreamEvent {
  final String content;
  final bool isDone;
  final int inputTokens;
  final int outputTokens;
  final double cost;
  final List<String> sourceChunks;
  // Server-driven classification of which subject/chapter this answer's
  // sources came from — the client no longer picks these up front.
  final String? subjectId;
  final String? subjectName;
  final String? chapterId;
  final String? chapterName;
  // Rich-answer envelope extras (only populated when the backend returned
  // a `richAnswer: true` response). `blocks` may be null/malformed — callers
  // must always be able to fall back to rendering `content` as markdown.
  final List<Map<String, dynamic>>? blocks;
  final List<Map<String, dynamic>> sources;
  final String? speechText;
  // Set instead of a normal answer when the backend wants confirmation
  // before answering from a beta (not-yet-verified) chapter. When true,
  // `content` is empty and callers must prompt the user rather than treat
  // this as a completed/empty answer.
  final bool needsBetaConfirmation;
  final String? betaChapterId;
  final String? betaChapterName;
  final String? betaSubjectName;
  final String? betaMessage;

  const ChatAIStreamEvent({
    required this.content,
    this.isDone = false,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost = 0,
    this.sourceChunks = const [],
    this.subjectId,
    this.subjectName,
    this.chapterId,
    this.chapterName,
    this.blocks,
    this.sources = const [],
    this.speechText,
    this.needsBetaConfirmation = false,
    this.betaChapterId,
    this.betaChapterName,
    this.betaSubjectName,
    this.betaMessage,
  });
}

class ChatAIService {
  static final ChatAIService instance = ChatAIService._();
  ChatAIService._();

  final _settingsRepo = SettingsRepository();
  final _usageRepo = UsageLogRepository();
  final _chunkRepo = ChunkRepository();

  static const double _defaultInputPrice = 0.0005;
  static const double _defaultOutputPrice = 0.0015;

  /// Streams a chat answer incrementally from the real SSE endpoint
  /// (`/api/ai/chat/stream`). Yields a `ChatAIStreamEvent` per `chunk` with
  /// the full accumulated text so far (never `isDone`), then exactly one
  /// terminal event: either a normal `isDone` answer, a
  /// `needsBetaConfirmation` prompt, or a thrown [AppException] on error.
  ///
  /// Note: the streaming endpoint is plain-Markdown-only — it never returns
  /// `blocks` or `speechText` (no rich/JSON mode, no vision refinement pass;
  /// see apps/api's `ai_chat_stream` doc comment). Callers that need those
  /// must keep using the non-streaming path.
  Stream<ChatAIStreamEvent> streamMessage({
    required String userContent,
    String? imagePath,
    required String responseLength,
    required String reasoningLevel,
    String? responseLanguage,
    List<ChatMessage> history = const [],
    // Optional — only set when the user picked a chapter via the chapter
    // picker. Scopes backend Qdrant retrieval to just this chapter; null or
    // empty preserves the existing global-search behavior.
    List<String>? chapterIds,
    // Set when resending after the user tapped "Yes" on the beta-chapter
    // confirmation prompt — tells the backend to answer from that chapter
    // despite it being in beta.
    String? confirmBetaChapterId,
  }) async* {
    AIBackendService.requireChatApiKey();

    await _checkDailyLimit();

    final systemPrompt = AppPrompts.buildChatSystemPrompt(
      subjectName: null,
      contextBlock: '',
      reasoningLevel: reasoningLevel,
      responseLanguage: responseLanguage,
      responseLength: responseLength,
    );

    final recent = history.length > 18
        ? history.sublist(history.length - 18)
        : history;
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...recent.map(_toApiMsg),
      _buildUserMsg(userContent, imagePath),
    ];

    // The backend now embeds the question, searches Qdrant globally, and
    // reranks — the client just sends the question and lets the server
    // decide which subject/chapter context applies.
    final payload = {
      'messages': messages,
      'temperature': _temperature(reasoningLevel),
      'responseLength': responseLength,
      'reasoningLevel': reasoningLevel,
      'responseLanguage': responseLanguage,
      if (chapterIds != null && chapterIds.isNotEmpty)
        'chapterIds': chapterIds,
      'confirmBetaChapterId': ?confirmBetaChapterId,
    };

    // The stream contract doesn't return token usage, so cost/usage are
    // estimated client-side from prompt/response text — same estimator the
    // non-streaming path falls back to when the backend omits `usage`.
    final promptEstimate = _estimateTokens(jsonEncode(messages));
    final buffer = StringBuffer();
    var reachedTerminalEvent = false;

    await for (final event in AIBackendService.streamChatCompletions(
      payload: payload,
      connectTimeout: const Duration(seconds: 30),
    )) {
      switch (event.event) {
        case 'chunk':
          final delta = event.data['delta']?.toString() ?? '';
          if (delta.isEmpty) break;
          buffer.write(delta);
          yield ChatAIStreamEvent(content: buffer.toString());
          break;

        case 'beta':
          reachedTerminalEvent = true;
          yield ChatAIStreamEvent(
            content: '',
            isDone: true,
            needsBetaConfirmation: true,
            betaChapterId: event.data['chapterId'] as String?,
            betaChapterName: event.data['chapterName'] as String?,
            betaSubjectName: event.data['subjectName'] as String?,
            betaMessage: event.data['message'] as String?,
          );
          return;

        case 'done':
          reachedTerminalEvent = true;
          final content = buffer.toString().trim();
          final outputTokens = _estimateTokens(content);
          final cost = await _calculateCost(promptEstimate, outputTokens);
          final backendSources = _asMapList(event.data['sources']);

          await _usageRepo.insert(
            UsageLog(
              id: const Uuid().v4(),
              toolType: 'chat',
              inputTokensEstimate: promptEstimate,
              outputTokensEstimate: outputTokens,
              estimatedCost: cost,
              createdAt: DateTime.now(),
            ),
          );

          yield ChatAIStreamEvent(
            content: content,
            isDone: true,
            inputTokens: promptEstimate,
            outputTokens: outputTokens,
            cost: cost,
            subjectId: event.data['subjectId'] as String?,
            subjectName: event.data['subjectName'] as String?,
            chapterId: event.data['chapterId'] as String?,
            chapterName: event.data['chapterName'] as String?,
            sources: backendSources ?? const [],
          );
          return;

        case 'error':
          reachedTerminalEvent = true;
          throw _buildStreamException(event.data);

        default:
          // Unknown/keep-alive event types are ignored rather than treated
          // as fatal — forward compatible with server additions.
          break;
      }
    }

    if (!reachedTerminalEvent) {
      // The connection closed (or the stream ended) before any terminal
      // event (`done`/`beta`/`error`) arrived — a mid-stream disconnect.
      throw AppException.network(
        'The connection was lost before the response finished. Please try again.',
      );
    }
  }

  Future<String> generateChatName(String firstMessage) async {
    try {
      final model =
          await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';
      final resp = await AIBackendService.postChatCompletions(
        payload: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': AppPrompts.buildChatTitlePrompt(firstMessage),
            },
          ],
          'max_tokens': 20,
          'temperature': 0.3,
        },
        timeout: const Duration(seconds: 90),
      );
      if (resp.statusCode != 200) {
        return _truncate(firstMessage, 40);
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['choices'][0]['message']['content'] as String).trim();
    } catch (_) {
      return _truncate(firstMessage, 40);
    }
  }

  Future<void> _checkDailyLimit() async {
    final limitStr = await _settingsRepo.get(SettingKeys.chatDailyTokenLimit);
    final limit = int.tryParse(limitStr ?? '0') ?? 0;
    if (limit <= 0) {
      return;
    }

    final summary = await _usageRepo.getSummary();
    final todayOut = (summary['todayOutputTokens'] as int?) ?? 0;
    if (todayOut >= limit) {
      throw AppException.service(
        'Daily token limit of $limit tokens reached. Increase it in Settings -> Usage.',
      );
    }
  }

  Map<String, dynamic> _buildUserMsg(String content, String? imagePath) {
    final text = content.trim().isEmpty
        ? 'Please analyze this image and explain it.'
        : content;
    if (imagePath == null) {
      return {'role': 'user', 'content': text};
    }

    try {
      final bytes = File(imagePath).readAsBytesSync();
      final b64 = base64Encode(bytes);
      final ext = imagePath.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      return {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mime;base64,$b64', 'detail': 'auto'},
          },
        ],
      };
    } catch (_) {
      return {'role': 'user', 'content': text};
    }
  }

  Map<String, dynamic> _toApiMsg(ChatMessage message) => {
    'role': message.role,
    'content': message.imagePath != null
        ? '${message.content}\n[Image was attached]'
        : message.content,
  };

  double _temperature(String level) => switch (level) {
    'low' => 0.2,
    'high' => 0.7,
    _ => 0.4,
  };

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}...';

  Future<double> _calculateCost(int inputTokens, int outputTokens) async {
    final inputPrice =
        double.tryParse(
          await _settingsRepo.get(SettingKeys.inputTokenPrice) ?? '',
        ) ??
        _defaultInputPrice;
    final outputPrice =
        double.tryParse(
          await _settingsRepo.get(SettingKeys.outputTokenPrice) ?? '',
        ) ??
        _defaultOutputPrice;
    return (inputTokens / 1000) * inputPrice +
        (outputTokens / 1000) * outputPrice;
  }

  /// Defensively coerce a dynamic JSON value into a list of string-keyed
  /// maps. Returns null (not empty) when the value is absent/malformed so
  /// callers can distinguish "no blocks" from "backend sent something we
  /// couldn't parse" if they ever need to.
  List<Map<String, dynamic>>? _asMapList(dynamic value) {
    if (value is! List) return null;
    return value.whereType<Map>().map((item) {
      return item.map((key, value) => MapEntry(key.toString(), value));
    }).toList();
  }

  int _estimateTokens(String text) =>
      RetrievalService(_chunkRepo).estimateTokens(text);

  /// Classifies an `error` SseEvent's data into the right [AppException]
  /// type, mirroring the non-streaming path's status-code handling (see
  /// `AIBackendService._postJson`'s callers). `kind`/`statusCode` are set by
  /// [SseClient] itself for connection- and HTTP-status-level failures; a
  /// genuine `event: error` frame sent by the server carries neither and is
  /// treated as a generic service error.
  AppException _buildStreamException(Map<String, dynamic> data) {
    final message =
        data['message']?.toString() ??
        'The AI stream failed. Please try again.';
    final kind = data['kind'] as String?;

    if (kind == 'connection') {
      return AppException.network(message);
    }
    if (kind == 'httpStatus') {
      final statusCode = data['statusCode'] as int? ?? 0;
      if (statusCode == 401 || statusCode == 403) {
        return AppException.authentication('Sign in again and retry.');
      }
      if (statusCode == 429) {
        return AppException.rateLimit(message);
      }
      if (statusCode >= 500) {
        return AppException.service(
          'The backend is having trouble right now. Please try again soon.',
        );
      }
      return AppException.service(message);
    }
    return AppException.service(message);
  }
}
