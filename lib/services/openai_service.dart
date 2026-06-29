import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/prompts.dart';
import '../models/usage_log.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/retrieval_service.dart';
import 'package:uuid/uuid.dart';

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

  // Default pricing per 1000 tokens (overridable in settings)
  static const double _defaultInputPrice = 0.0005;   // $0.50 / 1M tokens
  static const double _defaultOutputPrice = 0.0015;  // $1.50 / 1M tokens

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
    final apiKey = await _settings.get(SettingKeys.openAiApiKey);
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw Exception('NO_API_KEY');
    }

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

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    ).timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      final msg = err['error']?['message'] ?? 'OpenAI API error ${response.statusCode}';
      throw Exception(msg);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final answer = data['choices'][0]['message']['content'] as String;

    // Token usage from API response
    final usage = data['usage'] as Map<String, dynamic>?;
    final inputTokens = (usage?['prompt_tokens'] as int?) ?? _retrieval.estimateTokens(userPrompt);
    final outputTokens = (usage?['completion_tokens'] as int?) ?? _retrieval.estimateTokens(answer);

    // Pricing
    final inPrice = double.tryParse(
            await _settings.get(SettingKeys.inputTokenPrice) ?? '') ??
        _defaultInputPrice;
    final outPrice = double.tryParse(
            await _settings.get(SettingKeys.outputTokenPrice) ?? '') ??
        _defaultOutputPrice;
    final cost = (inputTokens / 1000) * inPrice + (outputTokens / 1000) * outPrice;

    // Log usage
    await _usageLog.insert(UsageLog(
      id: Uuid().v4(),
      toolType: toolType,
      inputTokensEstimate: inputTokens,
      outputTokensEstimate: outputTokens,
      estimatedCost: cost,
      createdAt: DateTime.now(),
    ));

    return GenerationResult(
      answer: answer,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCost: cost,
    );
  }

  /// Generate embeddings for a list of texts.
  Future<List<List<double>>> generateEmbeddings(List<String> texts) async {
    final apiKey = await _settings.get(SettingKeys.openAiApiKey);
    if (apiKey == null || apiKey.trim().isEmpty) throw Exception('NO_API_KEY');

    final body = jsonEncode({
      'model': 'text-embedding-3-small',
      'input': texts,
    });

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/embeddings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Embedding API error ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final embedData = data['data'] as List;
    return embedData
        .map((e) => (e['embedding'] as List).map((v) => (v as num).toDouble()).toList())
        .toList();
  }
}
