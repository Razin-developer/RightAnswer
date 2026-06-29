import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../constants/prompts.dart';
import '../models/app_exception.dart';
import '../models/usage_log.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/retrieval_service.dart';

class GenerationResult {
  final String answer;
  final int inputTokens;
  final int outputTokens;
  final double estimatedCost;

  GenerationResult({
    required this.answer,
    required this.inputTokens,
    required this.outputTokens,
    required this.estimatedCost,
  });
}

/// Calls OpenAI chat completions and logs usage locally.
class OpenAIService {
  final SettingsRepository _settings;
  final UsageLogRepository _usageLog;
  final RetrievalService _retrieval;

  static const double _defaultInputPrice = 0.0005;
  static const double _defaultOutputPrice = 0.0015;

  OpenAIService(this._settings, this._usageLog, this._retrieval);

  Future<GenerationResult> generateFromContext({
    required String toolType,
    required String? question,
    required List<String> contextChunks,
    required String language,
    required String gradeLevel,
    required String tone,
    required String outputLength,
  }) async {
    final apiKey = _requireApiKey();
    final model = await _settings.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    final userPrompt = Prompts.buildFullPrompt(
      toolType: toolType,
      question: question,
      contextChunks: contextChunks,
      language: language,
      gradeLevel: gradeLevel,
      tone: tone,
      outputLength: outputLength,
    );

    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': Prompts.systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.3,
    });

    final response = await _postJson(
      endpoint: 'https://api.openai.com/v1/chat/completions',
      apiKey: apiKey,
      body: body,
      timeout: const Duration(seconds: 120),
    );

    if (response.statusCode != 200) {
      throw _buildApiException(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final answer = data['choices'][0]['message']['content'] as String;

    final usage = data['usage'] as Map<String, dynamic>?;
    final inputTokens =
        (usage?['prompt_tokens'] as int?) ??
        _retrieval.estimateTokens(userPrompt);
    final outputTokens =
        (usage?['completion_tokens'] as int?) ??
        _retrieval.estimateTokens(answer);

    final inPrice =
        double.tryParse(
          await _settings.get(SettingKeys.inputTokenPrice) ?? '',
        ) ??
        _defaultInputPrice;
    final outPrice =
        double.tryParse(
          await _settings.get(SettingKeys.outputTokenPrice) ?? '',
        ) ??
        _defaultOutputPrice;
    final cost =
        (inputTokens / 1000) * inPrice + (outputTokens / 1000) * outPrice;

    await _usageLog.insert(
      UsageLog(
        id: const Uuid().v4(),
        toolType: toolType,
        inputTokensEstimate: inputTokens,
        outputTokensEstimate: outputTokens,
        estimatedCost: cost,
        createdAt: DateTime.now(),
      ),
    );

    return GenerationResult(
      answer: answer,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCost: cost,
    );
  }

  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final apiKey = _requireApiKey();
    final body = jsonEncode({
      'model': 'text-embedding-3-small',
      'input': texts,
    });

    final response = await _postJson(
      endpoint: 'https://api.openai.com/v1/embeddings',
      apiKey: apiKey,
      body: body,
      timeout: const Duration(seconds: 60),
    );

    if (response.statusCode != 200) {
      throw _buildApiException(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final embedData = data['data'] as List;
    return embedData
        .map(
          (e) => (e['embedding'] as List)
              .map((v) => (v as num).toDouble())
              .toList(),
        )
        .toList();
  }

  String _requireApiKey() {
    final apiKey = AppConfig.openAiApiKey.trim();
    if (apiKey.isEmpty) {
      throw AppException.configuration(
        'Missing OpenAI API key. Build with --dart-define=OPENAI_API_KEY=your_key.',
      );
    }
    return apiKey;
  }

  Future<http.Response> _postJson({
    required String endpoint,
    required String apiKey,
    required String body,
    required Duration timeout,
  }) async {
    try {
      return await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AppException.network(
        'The request took too long. Please try again in a moment.',
      );
    } on SocketException {
      throw AppException.network(
        'No internet connection. Check your network and try again.',
      );
    } on http.ClientException {
      throw AppException.network(
        'Could not reach OpenAI. Please try again shortly.',
      );
    }
  }

  AppException _buildApiException(http.Response response) {
    var message = 'OpenAI returned an unexpected error.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      message = decoded['error']?['message'] as String? ?? message;
    } catch (_) {
      // Fall back to the generic message when the response is not JSON.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AppException.authentication(
        'The configured OpenAI API key was rejected. Check OPENAI_API_KEY and rebuild the app.',
      );
    }
    if (response.statusCode == 429) {
      return AppException.rateLimit(message);
    }
    if (response.statusCode >= 500) {
      return AppException.service(
        'OpenAI is having trouble right now. Please try again in a little while.',
      );
    }
    return AppException.service(message);
  }
}
