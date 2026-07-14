import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/app_exception.dart';

class AIHttpException implements Exception {
  final int statusCode;
  final String responseBody;
  final String providerName;

  const AIHttpException({
    required this.statusCode,
    required this.responseBody,
    required this.providerName,
  });
}

class AIStreamSession {
  final http.Client client;
  final http.StreamedResponse response;
  final String providerName;

  const AIStreamSession({
    required this.client,
    required this.response,
    required this.providerName,
  });
}

class AIBackendService {
  AIBackendService._();

  static const _openAiBaseUrl = 'https://api.openai.com/v1';
  static const _hackClubBaseUrl = 'https://ai.hackclub.com/proxy/v1';
  static const hackClubEmbeddingModel = 'google/gemini-embedding-2';

  static List<_AIProvider> _chatCompletionProviders() {
    final openAi = AppConfig.hasOpenAiApiKey
        ? _AIProvider(
            name: 'OpenAI',
            baseUrl: _openAiBaseUrl,
            apiKey: AppConfig.openAiApiKey.trim(),
            modelTransform: _openAiChatModel,
          )
        : null;
    final hackClub = AppConfig.hasHackClubApiKey
        ? _AIProvider(
            name: 'Hack Club AI',
            baseUrl: _hackClubBaseUrl,
            apiKey: AppConfig.hackClubApiKey.trim(),
            modelTransform: _hackClubChatModel,
          )
        : null;

    if (kDebugMode) {
      return [?hackClub, ?openAi];
    }
    return [?openAi, ?hackClub];
  }

  static List<_AIProvider> _embeddingProviders() {
    final hackClub = AppConfig.hasHackClubApiKey
        ? _AIProvider(
            name: 'Hack Club AI',
            baseUrl: _hackClubBaseUrl,
            apiKey: AppConfig.hackClubApiKey.trim(),
            modelTransform: (_) => hackClubEmbeddingModel,
          )
        : null;
    final openAi = AppConfig.hasOpenAiApiKey
        ? _AIProvider(
            name: 'OpenAI',
            baseUrl: _openAiBaseUrl,
            apiKey: AppConfig.openAiApiKey.trim(),
            modelTransform: _openAiEmbeddingModel,
          )
        : null;

    return [?hackClub, ?openAi];
  }

  static String _hackClubChatModel(String model) {
    if (model.contains('/')) {
      return model;
    }
    return 'openai/$model';
  }

  static String _openAiChatModel(String model) {
    if (model.startsWith('openai/')) {
      return model.substring('openai/'.length);
    }
    return model;
  }

  static String _openAiEmbeddingModel(String model) {
    if (model.startsWith('openai/')) {
      return model.substring('openai/'.length);
    }
    if (model.contains('/')) {
      return 'text-embedding-3-small';
    }
    return model;
  }

  static String requireChatApiKey() {
    final providers = _chatCompletionProviders();
    if (providers.isNotEmpty) {
      return providers.first.apiKey;
    }
    throw AppException.configuration(
      'Missing AI API key. Build with OPENAI_API_KEY or HACKCLUB_API_KEY.',
    );
  }

  static String requireEmbeddingApiKey() {
    final providers = _embeddingProviders();
    if (providers.isNotEmpty) {
      return providers.first.apiKey;
    }
    throw AppException.configuration(
      'Missing embedding API key. Build with HACKCLUB_API_KEY or OPENAI_API_KEY.',
    );
  }

  static Future<http.Response> postChatCompletions({
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    final providers = _chatCompletionProviders();
    if (providers.isEmpty) {
      requireChatApiKey();
    }

    return _postWithFallback(
      providers: providers,
      path: '/chat/completions',
      payload: payload,
      timeout: timeout,
      timeoutMessage:
          'The request took too long. Please try again in a moment.',
    );
  }

  static Future<AIStreamSession> startChatCompletionsStream({
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    final providers = _chatCompletionProviders();
    if (providers.isEmpty) {
      requireChatApiKey();
    }

    Object? lastError;
    AIHttpException? lastHttpError;

    for (final provider in providers) {
      final client = http.Client();
      try {
        final request = http.Request(
          'POST',
          Uri.parse('${provider.baseUrl}/chat/completions'),
        );
        request.headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${provider.apiKey}',
        });
        request.body = jsonEncode(provider.preparePayload(payload));

        final response = await client.send(request).timeout(timeout);
        if (response.statusCode == 200) {
          return AIStreamSession(
            client: client,
            response: response,
            providerName: provider.name,
          );
        }

        final errorBody = await response.stream.bytesToString();
        client.close();
        lastHttpError = AIHttpException(
          statusCode: response.statusCode,
          responseBody: errorBody,
          providerName: provider.name,
        );
      } on TimeoutException catch (error) {
        client.close();
        lastError = error;
      } on SocketException catch (error) {
        client.close();
        lastError = error;
      } on http.ClientException catch (error) {
        client.close();
        lastError = error;
      }
    }

    if (lastHttpError != null) {
      throw lastHttpError;
    }
    if (lastError is TimeoutException) {
      throw AppException.network(
        'The AI response took too long. Please try again.',
      );
    }
    if (lastError is SocketException) {
      throw AppException.network('No internet connection.');
    }
    if (lastError is http.ClientException) {
      throw AppException.network(
        'Could not reach the AI provider. Please try again shortly.',
      );
    }

    throw AppException.service('No AI provider is currently available.');
  }

  static Future<http.Response> postEmbeddings({
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    final providers = _embeddingProviders();
    if (providers.isEmpty) {
      requireEmbeddingApiKey();
    }

    return _postWithFallback(
      providers: providers,
      path: '/embeddings',
      payload: payload,
      timeout: timeout,
      timeoutMessage:
          'The embedding request took too long. Please try again in a moment.',
    );
  }

  static Future<http.Response> _postWithFallback({
    required List<_AIProvider> providers,
    required String path,
    required Map<String, dynamic> payload,
    required Duration timeout,
    required String timeoutMessage,
  }) async {
    http.Response? lastResponse;
    Object? lastError;

    for (final provider in providers) {
      try {
        final response = await http
            .post(
              Uri.parse('${provider.baseUrl}$path'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${provider.apiKey}',
              },
              body: jsonEncode(provider.preparePayload(payload)),
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          return response;
        }
        lastResponse = response;
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on http.ClientException catch (error) {
        lastError = error;
      }
    }

    if (lastResponse != null) {
      return lastResponse;
    }
    if (lastError is TimeoutException) {
      throw AppException.network(timeoutMessage);
    }
    if (lastError is SocketException) {
      throw AppException.network(
        'No internet connection. Check your network and try again.',
      );
    }
    if (lastError is http.ClientException) {
      throw AppException.network(
        'Could not reach the AI provider. Please try again shortly.',
      );
    }

    throw AppException.service('No AI provider is currently available.');
  }
}

class _AIProvider {
  final String name;
  final String baseUrl;
  final String apiKey;
  final String Function(String model) modelTransform;

  const _AIProvider({
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.modelTransform,
  });

  Map<String, dynamic> preparePayload(Map<String, dynamic> original) {
    final payload = Map<String, dynamic>.from(original);
    final model = payload['model'];
    if (model is String && model.trim().isNotEmpty) {
      payload['model'] = modelTransform(model.trim());
    }
    return payload;
  }
}
