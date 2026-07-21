import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/app_exception.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

class AIBackendService {
  AIBackendService._();

  static String requireChatApiKey() {
    if (AppConfig.hasApiUrl) {
      return AppConfig.apiUrl;
    }
    throw AppException.configuration('Missing API_URL for the backend.');
  }

  static String requireEmbeddingApiKey() => requireChatApiKey();

  static Future<http.Response> postChatCompletions({
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    requireChatApiKey();
    final backendPayload = _chatPayloadToBackend(payload);
    final response = await _postJson('/api/ai/chat', backendPayload, timeout);
    if (response.statusCode >= 400) {
      return response;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    // The backend can short-circuit a normal answer with a beta-chapter
    // confirmation prompt instead. Pass that shape straight through — the
    // caller (ChatAIService) checks for it before treating the response as
    // a regular answer.
    if (decoded['needsBetaConfirmation'] == true) {
      return http.Response(
        jsonEncode({
          'needsBetaConfirmation': true,
          'chapterId': decoded['chapterId'],
          'chapterName': decoded['chapterName'],
          'subjectName': decoded['subjectName'],
          'message': decoded['message'],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }

    final answer =
        (decoded['content'] as String?) ??
        (decoded['answer'] is Map<String, dynamic>
            ? (decoded['answer']['content'] as String?)
            : null) ??
        '';
    final answerMeta = decoded['answer'] is Map<String, dynamic>
        ? decoded['answer'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final inputTokens = (answerMeta['inputTokens'] as int?) ?? 0;
    final outputTokens = (answerMeta['outputTokens'] as int?) ?? 0;
    final sourceChunks = decoded['sourceChunks'] ?? answerMeta['sourceChunks'];
    final sources = decoded['sources'] ?? answerMeta['sources'];
    final blocks = decoded['blocks'] ?? answerMeta['blocks'];
    final speechText = decoded['speechText'] ?? answerMeta['speechText'];

    return http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': answer},
          },
        ],
        'usage': {
          'prompt_tokens': inputTokens,
          'completion_tokens': outputTokens,
        },
        'provider': answerMeta['provider'],
        'model': answerMeta['model'],
        'servedFrom': decoded['servedFrom'] ?? answerMeta['servedFrom'],
        if (sourceChunks is List) 'sourceChunks': sourceChunks,
        if (sources is List) 'sources': sources,
        'blocks': ?blocks,
        'speechText': ?speechText,
        // Server-driven classification of which subject/chapter this
        // answer's sources came from — the client no longer picks these.
        'subjectId': decoded['subjectId'],
        'subjectName': decoded['subjectName'],
        'chapterId': decoded['chapterId'],
        'chapterName': decoded['chapterName'],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  static Future<http.Response> postEmbeddings({
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    requireEmbeddingApiKey();
    final input = payload['input'];
    final texts = input is List
        ? input.map((value) => value.toString()).toList()
        : [input?.toString() ?? ''];

    final embeddings = <Map<String, dynamic>>[];
    for (final text in texts) {
      final response = await _postJson(
        '/api/ai/embeddings',
        {'text': text},
        timeout,
      );
      if (response.statusCode >= 400) {
        return response;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      embeddings.add({'embedding': decoded['embedding'] ?? const []});
    }

    return http.Response(
      jsonEncode({'data': embeddings}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  static Map<String, dynamic> _chatPayloadToBackend(
    Map<String, dynamic> payload,
  ) {
    final messages = (payload['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final systemPrompts = <String>[];
    final history = <Map<String, String>>[];
    String question = '';

    for (final message in messages) {
      final role = message['role'] as String? ?? 'user';
      final content = _contentToText(message['content']);
      if (role == 'system') {
        systemPrompts.add(content);
      } else if (role == 'user') {
        if (content.trim().isNotEmpty) {
          question = content;
        }
      } else if (role == 'assistant') {
        history.add({'role': 'assistant', 'content': content});
      }
    }

    if (question.trim().isEmpty && messages.isNotEmpty) {
      question = _contentToText(messages.last['content']);
    }

    final responseFormat = payload['response_format'];
    return {
      'question': question,
      if (systemPrompts.isNotEmpty) 'systemPrompt': systemPrompts.join('\n\n'),
      if (history.isNotEmpty) 'history': history,
      if (payload['temperature'] != null) 'temperature': payload['temperature'],
      if (payload['max_tokens'] != null) 'maxTokens': payload['max_tokens'],
      if (responseFormat is Map &&
          responseFormat['type'] == 'json_object') ...{
        'jsonMode': true,
        'responseFormat': 'json',
      },
      if (payload['contexts'] is List) 'contexts': payload['contexts'],
      if (payload['responseLength'] != null)
        'responseLength': payload['responseLength'],
      if (payload['reasoningLevel'] != null)
        'reasoningLevel': payload['reasoningLevel'],
      if (payload['responseLanguage'] != null)
        'responseLanguage': payload['responseLanguage'],
      if (payload['richAnswer'] == true) 'richAnswer': true,
      if (payload['answerFormat'] != null) 'answerFormat': payload['answerFormat'],
      // Set when the user confirmed they want an answer sourced from a
      // beta chapter after the backend asked for confirmation.
      if (payload['confirmBetaChapterId'] != null)
        'confirmBetaChapterId': payload['confirmBetaChapterId'],
      // Optional retrieval scoping — only present when the user actively
      // picked a chapter via the chapter picker. Absent/empty means the
      // backend searches globally, exactly as before.
      if (payload['chapterIds'] is List &&
          (payload['chapterIds'] as List).isNotEmpty)
        'chapterIds': (payload['chapterIds'] as List)
            .map((e) => e.toString())
            .toList(),
    };
  }

  static String _contentToText(dynamic content) {
    if (content is String) {
      return content;
    }
    if (content is List) {
      return content
          .map((part) {
            if (part is Map && part['type'] == 'text') {
              return part['text']?.toString() ?? '';
            }
            if (part is Map && part['type'] == 'image_url') {
              return '[Image attachment included]';
            }
            return '';
          })
          .where((part) => part.trim().isNotEmpty)
          .join('\n');
    }
    return content?.toString() ?? '';
  }

  static Future<http.Response> _postJson(
    String path,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    if (!ConnectivityService.instance.isOnline) {
      throw AppException.network(
        "You're offline — connect to the internet to use AI features.",
      );
    }

    final token = await AuthService.instance.getToken();
    try {
      return await http
          .post(
            Uri.parse('${AppConfig.apiUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AppException.network(
        'The backend took too long. Please try again in a moment.',
      );
    } on SocketException {
      throw AppException.network(
        'No internet connection. Check your network and try again.',
      );
    } on http.ClientException {
      throw AppException.network(
        'Could not reach the backend. Please try again shortly.',
      );
    }
  }
}
