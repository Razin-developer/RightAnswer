import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../constants/app_prompts.dart';
import '../models/app_exception.dart';
import '../models/usage_log.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import 'ai_backend_service.dart';
import 'retrieval_service.dart';

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

class ImageTextExtractionResult {
  final String combinedText;
  final int processedCount;
  final List<String> failedFiles;

  const ImageTextExtractionResult({
    required this.combinedText,
    required this.processedCount,
    required this.failedFiles,
  });
}

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
    final model = await _settings.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    final userPrompt = AppPrompts.buildChapterToolPrompt(
      toolType: toolType,
      question: question,
      contextChunks: contextChunks,
      language: language,
      gradeLevel: gradeLevel,
      tone: tone,
      outputLength: outputLength,
    );

    final response = await AIBackendService.postChatCompletions(
      payload: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': AppPrompts.chapterTutorSystemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': 0.3,
      },
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
    final response = await AIBackendService.postEmbeddings(
      payload: {'model': 'text-embedding-3-small', 'input': texts},
      timeout: const Duration(seconds: 60),
    );

    if (response.statusCode != 200) {
      throw _buildApiException(response);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final embedData = data['data'] as List;
    return embedData
        .map(
          (entry) => (entry['embedding'] as List)
              .map((value) => (value as num).toDouble())
              .toList(),
        )
        .toList();
  }

  Future<ImageTextExtractionResult> extractChapterTextFromImages({
    required List<String> imagePaths,
    required String chapterTitle,
    String? subjectName,
  }) async {
    if (imagePaths.isEmpty) {
      throw AppException.validation(
        'Select at least one textbook image first.',
      );
    }

    final model = await _settings.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';
    final extracted = <String>[];
    final failed = <String>[];
    var totalInputTokens = 0;
    var totalOutputTokens = 0;

    for (final imagePath in imagePaths) {
      try {
        final bytes = File(imagePath).readAsBytesSync();
        final b64 = base64Encode(bytes);
        final ext = imagePath.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';

        final response = await AIBackendService.postChatCompletions(
          payload: {
            'model': model,
            'messages': [
              {
                'role': 'system',
                'content': AppPrompts.imageExtractionSystemPrompt,
              },
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'text',
                    'text': AppPrompts.buildImageExtractionUserPrompt(
                      chapterTitle: chapterTitle,
                      subjectName: subjectName,
                    ),
                  },
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:$mime;base64,$b64',
                      'detail': 'high',
                    },
                  },
                ],
              },
            ],
            'temperature': 0.1,
          },
          timeout: const Duration(seconds: 120),
        );

        if (response.statusCode != 200) {
          throw _buildApiException(response);
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['choices'][0]['message']['content'] as String)
            .trim();
        if (text.isNotEmpty) {
          extracted.add(text);
        }

        final usage = data['usage'] as Map<String, dynamic>?;
        totalInputTokens += (usage?['prompt_tokens'] as int?) ?? 0;
        totalOutputTokens += (usage?['completion_tokens'] as int?) ?? 0;
      } catch (_) {
        failed.add(imagePath.split(RegExp(r'[\\/]')).last);
      }
    }

    if (extracted.isEmpty) {
      throw AppException.service(
        'The selected textbook images could not be read. Try clearer photos with better lighting.',
      );
    }

    final combinedText = extracted.join('\n\n--- Page Break ---\n\n');
    if (totalInputTokens > 0 || totalOutputTokens > 0) {
      final inputPrice =
          double.tryParse(
            await _settings.get(SettingKeys.inputTokenPrice) ?? '',
          ) ??
          _defaultInputPrice;
      final outputPrice =
          double.tryParse(
            await _settings.get(SettingKeys.outputTokenPrice) ?? '',
          ) ??
          _defaultOutputPrice;
      final cost =
          (totalInputTokens / 1000) * inputPrice +
          (totalOutputTokens / 1000) * outputPrice;
      await _usageLog.insert(
        UsageLog(
          id: const Uuid().v4(),
          toolType: 'chapter_image_extract',
          inputTokensEstimate: totalInputTokens,
          outputTokensEstimate: totalOutputTokens,
          estimatedCost: cost,
          createdAt: DateTime.now(),
        ),
      );
    }

    return ImageTextExtractionResult(
      combinedText: combinedText,
      processedCount: extracted.length,
      failedFiles: failed,
    );
  }

  AppException _buildApiException(http.Response response) {
    var message = 'The AI provider returned an unexpected error.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      message = decoded['error']?['message'] as String? ?? message;
    } catch (_) {
      // Keep the default message when the response body is not JSON.
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return AppException.authentication(
        'The configured AI API key was rejected. Check your debug or release API configuration and rebuild the app.',
      );
    }
    if (response.statusCode == 429) {
      return AppException.rateLimit(message);
    }
    if (response.statusCode >= 500) {
      return AppException.service(
        'The AI provider is having trouble right now. Please try again in a little while.',
      );
    }
    return AppException.service(message);
  }
}
