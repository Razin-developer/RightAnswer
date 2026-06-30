import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/app_exception.dart';
import '../models/chat_message.dart';
import '../models/usage_log.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/retrieval_service.dart';

class ChatAIResult {
  final String content;
  final int inputTokens;
  final int outputTokens;
  final double cost;

  const ChatAIResult({
    required this.content,
    required this.inputTokens,
    required this.outputTokens,
    required this.cost,
  });
}

class ChatAIStreamEvent {
  final String content;
  final bool isDone;
  final int inputTokens;
  final int outputTokens;
  final double cost;

  const ChatAIStreamEvent({
    required this.content,
    this.isDone = false,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost = 0,
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
        );
      }
    }
    if (result != null) return result;
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
    final apiKey = _requireApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    await _checkDailyLimit();

    final contextBlock = await _buildContextBlock(chapterIds, userContent);
    final systemPrompt = _buildSystemPrompt(
      subjectName,
      contextBlock,
      reasoningLevel,
      responseLanguage,
    );

    final recent = history.length > 18
        ? history.sublist(history.length - 18)
        : history;
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...recent.map(_toApiMsg),
      _buildUserMsg(userContent, imagePath),
    ];

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': _temperature(reasoningLevel),
      'max_tokens': _maxTokens(responseLength),
      'stream': true,
      'stream_options': {'include_usage': true},
    });

    final promptEstimate = _estimateTokens(jsonEncode(messages));
    final client = http.Client();
    final buffer = StringBuffer();
    Map<String, dynamic>? usage;

    try {
      final request = http.Request(
        'POST',
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      });
      request.body = body;

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw _buildException(http.Response(errorBody, response.statusCode));
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 120));

      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        if (payload == '[DONE]') break;

        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        final usageBlock = decoded['usage'] as Map<String, dynamic>?;
        if (usageBlock != null) usage = usageBlock;

        final choices = decoded['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
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
      );
    } on TimeoutException {
      throw AppException.network(
        'The AI response took too long. Please try again.',
      );
    } on SocketException {
      throw AppException.network('No internet connection.');
    } on http.ClientException {
      throw AppException.network(
        'Could not reach OpenAI. Please try again shortly.',
      );
    } finally {
      client.close();
    }
  }

  Future<String> generateChatName(String firstMessage) async {
    try {
      final apiKey = _requireApiKey();
      final model =
          await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';
      final body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content':
                'In 3-5 words, give a concise chat title. Reply with ONLY the title, no punctuation or quotes:\n"$firstMessage"',
          },
        ],
        'max_tokens': 20,
        'temperature': 0.3,
      });
      final resp = await _post(
        'https://api.openai.com/v1/chat/completions',
        apiKey,
        body,
      );
      if (resp.statusCode != 200) return _truncate(firstMessage, 40);
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['choices'][0]['message']['content'] as String).trim();
    } catch (_) {
      return _truncate(firstMessage, 40);
    }
  }

  Future<void> _checkDailyLimit() async {
    final limitStr = await _settingsRepo.get(SettingKeys.chatDailyTokenLimit);
    final limit = int.tryParse(limitStr ?? '0') ?? 0;
    if (limit <= 0) return;
    final summary = await _usageRepo.getSummary();
    final todayOut = (summary['todayOutputTokens'] as int?) ?? 0;
    if (todayOut >= limit) {
      throw AppException.service(
        'Daily token limit of $limit tokens reached. Increase it in Settings → Usage.',
      );
    }
  }

  Future<String> _buildContextBlock(
    List<String> chapterIds,
    String userContent,
  ) async {
    if (chapterIds.isEmpty) return '';
    final retrieval = RetrievalService(_chunkRepo);
    final chunks = <String>[];
    for (final chapterId in chapterIds) {
      final found = await retrieval.searchChapter(
        chapterId,
        userContent.isEmpty ? 'overview' : userContent,
      );
      chunks.addAll(found.map((chunk) => chunk.text));
    }
    if (chunks.isEmpty) return '';
    final joined = chunks.take(6).join('\n\n');
    return '\n\nSTUDY MATERIAL:\n$joined';
  }

  String _buildSystemPrompt(
    String? subjectName,
    String contextBlock,
    String reasoningLevel,
    String? responseLanguage,
  ) {
    final reasoning = switch (reasoningLevel) {
      'high' =>
        '\n\nReason through each answer step by step, showing your work clearly.',
      'mid' => '\n\nThink carefully before answering.',
      _ => '',
    };
    final languageInstruction =
        responseLanguage == null || responseLanguage.trim().isEmpty
        ? '\n\nReply in the same language the user is using unless they explicitly ask you to translate or switch languages.'
        : '\n\nReply entirely in $responseLanguage unless the user explicitly asks you to switch languages.';

    if (contextBlock.isEmpty) {
      return 'You are RightAnswer, a helpful AI tutor for students. '
          'Answer questions clearly, accurately, and in an educational way.'
          '$reasoning$languageInstruction';
    }
    return 'You are RightAnswer, an AI tutor for ${subjectName ?? 'this subject'}. '
        'Use the provided study material to answer questions accurately. '
        'If a question is clearly outside this material, answer helpfully but note it may be beyond the current scope.'
        '$reasoning$languageInstruction$contextBlock';
  }

  Map<String, dynamic> _buildUserMsg(String content, String? imagePath) {
    final text = content.trim().isEmpty
        ? 'Please analyze this image and explain it.'
        : content;
    if (imagePath == null) return {'role': 'user', 'content': text};
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

  int _maxTokens(String length) => switch (length) {
    'small' => 200,
    'large' => 1500,
    _ => 600,
  };

  double _temperature(String level) => switch (level) {
    'low' => 0.2,
    'high' => 0.7,
    _ => 0.4,
  };

  String _truncate(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}...';

  String _requireApiKey() {
    final key = AppConfig.openAiApiKey.trim();
    if (key.isEmpty) {
      throw AppException.configuration(
        'Missing OpenAI API key. Build with --dart-define=OPENAI_API_KEY=your_key.',
      );
    }
    return key;
  }

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

  Future<http.Response> _post(String url, String apiKey, String body) async {
    try {
      return await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw AppException.network('Request timed out. Please try again.');
    } on SocketException {
      throw AppException.network('No internet connection.');
    } on http.ClientException {
      throw AppException.network(
        'Could not reach OpenAI. Please try again shortly.',
      );
    }
  }

  AppException _buildException(http.Response response) {
    var message = 'Unexpected error from OpenAI.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      message = decoded['error']?['message'] as String? ?? message;
    } catch (_) {
      // Fall back to the generic message if the response is not JSON.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AppException.authentication('Invalid API key.');
    }
    if (response.statusCode == 429) return AppException.rateLimit(message);
    if (response.statusCode >= 500) {
      return AppException.service(
        'OpenAI is having trouble right now. Please try again soon.',
      );
    }
    return AppException.service(message);
  }
}
