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

class ChatAIResult {
  final String content;
  final int inputTokens;
  final int outputTokens;
  final double cost;
  final List<String> sourceChunks;

  const ChatAIResult({
    required this.content,
    required this.inputTokens,
    required this.outputTokens,
    required this.cost,
    this.sourceChunks = const [],
  });
}

class ChatAIStreamEvent {
  final String content;
  final bool isDone;
  final int inputTokens;
  final int outputTokens;
  final double cost;
  final List<String> sourceChunks;

  const ChatAIStreamEvent({
    required this.content,
    this.isDone = false,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost = 0,
    this.sourceChunks = const [],
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

  Future<ChatAIResult> sendMessage({
    required String userContent,
    String? imagePath,
    required String responseLength,
    required String reasoningLevel,
    String? responseLanguage,
    String? subjectName,
    List<String> chapterIds = const [],
    List<ChatMessage> history = const [],
  }) async {
    ChatAIResult? result;
    await for (final event in streamMessage(
      userContent: userContent,
      imagePath: imagePath,
      responseLength: responseLength,
      reasoningLevel: reasoningLevel,
      responseLanguage: responseLanguage,
      subjectName: subjectName,
      chapterIds: chapterIds,
      history: history,
    )) {
      if (event.isDone) {
        result = ChatAIResult(
          content: event.content,
          inputTokens: event.inputTokens,
          outputTokens: event.outputTokens,
          cost: event.cost,
          sourceChunks: event.sourceChunks,
        );
      }
    }

    if (result != null) {
      return result;
    }
    return const ChatAIResult(
      content: '',
      inputTokens: 0,
      outputTokens: 0,
      cost: 0,
    );
  }

  Stream<ChatAIStreamEvent> streamMessage({
    required String userContent,
    String? imagePath,
    required String responseLength,
    required String reasoningLevel,
    String? responseLanguage,
    String? subjectName,
    List<String> chapterIds = const [],
    List<ChatMessage> history = const [],
  }) async* {
    AIBackendService.requireChatApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    await _checkDailyLimit();

    final (contextBlock, sourceChunks) = await _buildContextBlock(
      chapterIds,
      userContent,
    );
    final systemPrompt = AppPrompts.buildChatSystemPrompt(
      subjectName: subjectName,
      contextBlock: contextBlock,
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

    final payload = {
      'model': model,
      'messages': messages,
      'temperature': _temperature(reasoningLevel),
      'max_tokens': 4096,
      'stream': true,
      'stream_options': {'include_usage': true},
    };

    final promptEstimate = _estimateTokens(jsonEncode(messages));
    final buffer = StringBuffer();
    Map<String, dynamic>? usage;
    AIStreamSession? session;

    try {
      session = await AIBackendService.startChatCompletionsStream(
        payload: payload,
        timeout: const Duration(seconds: 30),
      );

      final lines = session.response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 120));

      await for (final line in lines) {
        if (!line.startsWith('data:')) {
          continue;
        }

        final payloadLine = line.substring(5).trim();
        if (payloadLine.isEmpty) {
          continue;
        }
        if (payloadLine == '[DONE]') {
          break;
        }

        final decoded = jsonDecode(payloadLine) as Map<String, dynamic>;
        final usageBlock = decoded['usage'] as Map<String, dynamic>?;
        if (usageBlock != null) {
          usage = usageBlock;
        }

        final choices = decoded['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          continue;
        }

        final delta = choices.first['delta'] as Map<String, dynamic>?;
        final piece = delta?['content'];
        if (piece is String && piece.isNotEmpty) {
          buffer.write(piece);
          yield ChatAIStreamEvent(content: buffer.toString());
        }
      }

      final content = buffer.toString().trim();
      final inputTokens = (usage?['prompt_tokens'] as int?) ?? promptEstimate;
      final outputTokens =
          (usage?['completion_tokens'] as int?) ?? _estimateTokens(content);
      final cost = await _calculateCost(inputTokens, outputTokens);

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
        sourceChunks: sourceChunks,
      );
    } on AIHttpException catch (error) {
      throw _buildException(
        http.Response(error.responseBody, error.statusCode),
      );
    } on TimeoutException {
      throw AppException.network(
        'The AI response took too long. Please try again.',
      );
    } on SocketException {
      throw AppException.network('No internet connection.');
    } on http.ClientException {
      throw AppException.network(
        'Could not reach the AI provider. Please try again shortly.',
      );
    } finally {
      session?.client.close();
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

  Future<(String, List<String>)> _buildContextBlock(
    List<String> chapterIds,
    String userContent,
  ) async {
    if (chapterIds.isEmpty) {
      return ('', <String>[]);
    }

    final retrieval = RetrievalService(_chunkRepo);
    final chunks = <String>[];
    for (final chapterId in chapterIds) {
      final found = await retrieval.searchChapter(
        chapterId,
        userContent.isEmpty ? 'overview' : userContent,
      );
      chunks.addAll(found.map((chunk) => chunk.text));
    }

    if (chunks.isEmpty) {
      return ('', <String>[]);
    }

    final taken = chunks.take(6).toList();
    final joined = taken.join('\n\n');
    return ('\n\nSTUDY MATERIAL:\n$joined', taken);
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
    var message = 'Unexpected error from the AI provider.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      message = decoded['error']?['message'] as String? ?? message;
    } catch (_) {
      // Fall back to the generic message if the response is not JSON.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AppException.authentication('Invalid API key.');
    }
    if (response.statusCode == 429) {
      return AppException.rateLimit(message);
    }
    if (response.statusCode >= 500) {
      return AppException.service(
        'The AI provider is having trouble right now. Please try again soon.',
      );
    }
    return AppException.service(message);
  }
}
