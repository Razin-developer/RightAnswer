import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
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
  }) async* {
    AIBackendService.requireChatApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

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
      'model': model,
      'messages': messages,
      'temperature': _temperature(reasoningLevel),
      'max_tokens': 4096,
      'responseLength': responseLength,
      'reasoningLevel': reasoningLevel,
      'responseLanguage': responseLanguage,
      'richAnswer': true,
      'answerFormat': 'rich',
      if (chapterIds != null && chapterIds.isNotEmpty)
        'chapterIds': chapterIds,
    };

    final promptEstimate = _estimateTokens(jsonEncode(messages));

    try {
      final resp = await AIBackendService.postChatCompletions(
        payload: payload,
        timeout: const Duration(seconds: 120),
      );
      if (resp.statusCode != 200) {
        throw _buildException(resp);
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final content =
          (data['choices'][0]['message']['content'] as String).trim();
      final usage = data['usage'] as Map<String, dynamic>?;
      final inputTokens = (usage?['prompt_tokens'] as int?) ?? promptEstimate;
      final outputTokens =
          (usage?['completion_tokens'] as int?) ?? _estimateTokens(content);
      final cost = await _calculateCost(inputTokens, outputTokens);
      final backendSourceChunks = data['sourceChunks'] is List
          ? List<String>.from(
              (data['sourceChunks'] as List).map((value) => value.toString()),
            )
          : const <String>[];

      await _usageRepo.insert(
        UsageLog(
          id: const Uuid().v4(),
          toolType: 'chat',
          inputTokensEstimate: inputTokens,
          outputTokensEstimate: outputTokens,
          estimatedCost: cost,
          createdAt: DateTime.now(),
        ),
      );

      yield ChatAIStreamEvent(
        content: content,
        isDone: true,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cost: cost,
        sourceChunks: backendSourceChunks,
        subjectId: data['subjectId'] as String?,
        subjectName: data['subjectName'] as String?,
        chapterId: data['chapterId'] as String?,
        chapterName: data['chapterName'] as String?,
      );
    } on TimeoutException {
      throw AppException.network(
        'The AI response took too long. Please try again.',
      );
    } on SocketException {
      throw AppException.network('No internet connection.');
    } on http.ClientException {
      throw AppException.network(
        'Could not reach the backend. Please try again shortly.',
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

  int _estimateTokens(String text) =>
      RetrievalService(_chunkRepo).estimateTokens(text);

  AppException _buildException(http.Response response) {
    var message = 'Unexpected error from the backend.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      message = decoded['error']?['message'] as String? ?? message;
    } catch (_) {
      // Fall back to the generic message if the response is not JSON.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AppException.authentication('Sign in again and retry.');
    }
    if (response.statusCode == 429) {
      return AppException.rateLimit(message);
    }
    if (response.statusCode >= 500) {
      return AppException.service(
        'The backend is having trouble right now. Please try again soon.',
      );
    }
    return AppException.service(message);
  }
}
