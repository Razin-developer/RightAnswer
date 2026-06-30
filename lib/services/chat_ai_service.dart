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
    String? subjectName,
    List<String> chapterIds = const [],
    List<ChatMessage> history = const [],
  }) async {
    final apiKey = _requireApiKey();
    final model = await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    await _checkDailyLimit();

    // Gather relevant context chunks from selected chapters
    String contextBlock = '';
    if (chapterIds.isNotEmpty) {
      final retrieval = RetrievalService(_chunkRepo);
      final chunks = <String>[];
      for (final cid in chapterIds) {
        final found = await retrieval.searchChapter(cid, userContent.isEmpty ? 'overview' : userContent);
        chunks.addAll(found.map((c) => c.text));
      }
      if (chunks.isNotEmpty) {
        final joined = chunks.take(6).join('\n\n');
        contextBlock = '\n\nSTUDY MATERIAL:\n$joined';
      }
    }

    final systemPrompt = _buildSystemPrompt(subjectName, contextBlock, reasoningLevel);

    // Cap history to last 18 messages to stay within token limits
    final recent = history.length > 18 ? history.sublist(history.length - 18) : history;

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
    });

    final resp = await _post('https://api.openai.com/v1/chat/completions', apiKey, body);
    if (resp.statusCode != 200) throw _buildException(resp);

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = data['choices'][0]['message']['content'] as String;
    final usage = data['usage'] as Map<String, dynamic>?;
    final inTok = (usage?['prompt_tokens'] as int?) ?? 0;
    final outTok = (usage?['completion_tokens'] as int?) ?? 0;

    final inPrice =
        double.tryParse(await _settingsRepo.get(SettingKeys.inputTokenPrice) ?? '') ?? _defaultInputPrice;
    final outPrice =
        double.tryParse(await _settingsRepo.get(SettingKeys.outputTokenPrice) ?? '') ?? _defaultOutputPrice;
    final cost = (inTok / 1000) * inPrice + (outTok / 1000) * outPrice;

    await _usageRepo.insert(UsageLog(
      id: const Uuid().v4(),
      toolType: 'chat',
      inputTokensEstimate: inTok,
      outputTokensEstimate: outTok,
      estimatedCost: cost,
      createdAt: DateTime.now(),
    ));

    return ChatAIResult(content: content, inputTokens: inTok, outputTokens: outTok, cost: cost);
  }

  Future<String> generateChatName(String firstMessage) async {
    try {
      final apiKey = _requireApiKey();
      final model = await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';
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
      final resp = await _post('https://api.openai.com/v1/chat/completions', apiKey, body);
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

  String _buildSystemPrompt(String? subjectName, String contextBlock, String reasoningLevel) {
    final reasoning = switch (reasoningLevel) {
      'high' => '\n\nReason through each answer step by step, showing your work clearly.',
      'mid' => '\n\nThink carefully before answering.',
      _ => '',
    };
    if (contextBlock.isEmpty) {
      return 'You are RightAnswer, a helpful AI tutor for students. '
          'Answer questions clearly, accurately, and in an educational way.$reasoning';
    }
    return 'You are RightAnswer, an AI tutor for ${subjectName ?? 'this subject'}. '
        'Use the provided study material to answer questions accurately. '
        'If a question is clearly outside this material, answer helpfully but note it may be beyond the current scope.$reasoning$contextBlock';
  }

  Map<String, dynamic> _buildUserMsg(String content, String? imagePath) {
    final text = content.trim().isEmpty ? 'Please analyze this image and explain it.' : content;
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

  Map<String, dynamic> _toApiMsg(ChatMessage m) => {
    'role': m.role,
    'content': m.imagePath != null ? '${m.content}\n[Image was attached]' : m.content,
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

  String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}...';

  String _requireApiKey() {
    final k = AppConfig.openAiApiKey.trim();
    if (k.isEmpty) {
      throw AppException.configuration(
        'Missing OpenAI API key. Build with --dart-define=OPENAI_API_KEY=your_key.',
      );
    }
    return k;
  }

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
    }
  }

  AppException _buildException(http.Response r) {
    var msg = 'Unexpected error from OpenAI.';
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      msg = d['error']?['message'] as String? ?? msg;
    } catch (_) {}
    if (r.statusCode == 401 || r.statusCode == 403) return AppException.authentication('Invalid API key.');
    if (r.statusCode == 429) return AppException.rateLimit(msg);
    return AppException.service(msg);
  }
}
