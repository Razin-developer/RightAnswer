import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/app_exception.dart';
import '../models/exam_message.dart';
import '../models/exam_question.dart';
import '../models/usage_log.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import 'ai_backend_service.dart';
import '../services/retrieval_service.dart';

class ExamGenerationResult {
  final String title;
  final List<ExamQuestion> questions;

  const ExamGenerationResult({required this.title, required this.questions});
}

class ExamAIService {
  static final ExamAIService instance = ExamAIService._();
  ExamAIService._();

  final _settingsRepo = SettingsRepository();
  final _usageRepo = UsageLogRepository();
  final _chunkRepo = ChunkRepository();

  static const double _defaultInputPrice = 0.0005;
  static const double _defaultOutputPrice = 0.0015;
  static const int _creationHarnessPasses = 4;

  // ── Generate from scratch ────────────────────────────────────────────────

  Future<ExamGenerationResult> generateExam({
    required String prompt,
    required String type,
    required int questionCount,
    required String difficulty,
    required int mcqOptionCount,
    int? timeLimit,
    String? subjectName,
    List<String> chapterIds = const [],
    String? imagePath,
  }) async {
    AIBackendService.requireChatApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    // Gather context chunks
    final contextBlock = await _buildContextBlock(chapterIds, prompt);

    final systemPrompt = _buildGenerationSystemPrompt(
      type: type,
      questionCount: questionCount,
      difficulty: difficulty,
      mcqOptionCount: mcqOptionCount,
      subjectName: subjectName,
      contextBlock: contextBlock,
    );

    final userMsg = _buildUserMsg(
      prompt.trim().isEmpty ? 'Generate $questionCount questions.' : prompt,
      imagePath,
    );

    final resp = await AIBackendService.postChatCompletions(
      payload: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          userMsg,
        ],
        if (contextBlock.isNotEmpty) 'contexts': [contextBlock],
        'temperature': 0.5,
        'max_tokens': 4000,
        'response_format': {'type': 'json_object'},
      },
      timeout: const Duration(seconds: 120),
    );
    if (resp.statusCode != 200) throw _buildException(resp);

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = data['choices'][0]['message']['content'] as String;
    await _logUsage(data, 'exam_generate');

    final draft = _parseResponse(content, '', type);
    return _runCreationHarness(
      draft: draft,
      model: model,
      prompt: prompt,
      type: type,
      questionCount: questionCount,
      difficulty: difficulty,
      mcqOptionCount: mcqOptionCount,
      subjectName: subjectName,
      contextBlock: contextBlock,
    );
  }

  // ── Edit existing exam ───────────────────────────────────────────────────

  Future<ExamGenerationResult> editExam({
    required String editPrompt,
    required String examType,
    required String examName,
    required List<ExamQuestion> currentQuestions,
    required List<ExamMessage> history,
    String? imagePath,
    String? subjectName,
    List<String> chapterIds = const [],
  }) async {
    AIBackendService.requireChatApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    final contextBlock = await _buildContextBlock(chapterIds, editPrompt);
    final currentJson = _questionsToJson(examName, currentQuestions);

    final systemPrompt = _buildEditSystemPrompt(
      examType: examType,
      subjectName: subjectName,
      contextBlock: contextBlock,
      currentExamJson: currentJson,
    );

    // Cap history at 16 messages
    final recent = history.length > 16
        ? history.sublist(history.length - 16)
        : history;

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...recent.map(
        (m) => {
          'role': m.role,
          'content': m.imagePath != null
              ? '${m.content}\n[Image attached]'
              : m.content,
        },
      ),
      _buildUserMsg(editPrompt, imagePath),
    ];

    final resp = await AIBackendService.postChatCompletions(
      payload: {
        'model': model,
        'messages': messages,
        if (contextBlock.isNotEmpty) 'contexts': [contextBlock],
        'temperature': 0.4,
        'max_tokens': 4000,
        'response_format': {'type': 'json_object'},
      },
      timeout: const Duration(seconds: 120),
    );
    if (resp.statusCode != 200) throw _buildException(resp);

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final content = data['choices'][0]['message']['content'] as String;
    await _logUsage(data, 'exam_edit');

    return _parseResponse(content, examName, examType);
  }

  // ── Auto-name ────────────────────────────────────────────────────────────

  Future<String> generateExamName(String prompt, String type) async {
    try {
      AIBackendService.requireChatApiKey();
      final model =
          await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';
      final typeLabel = _typeLabel(type);
      final resp = await AIBackendService.postChatCompletions(
        payload: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content':
                  'Create a 3-5 word title for a $typeLabel exam about: "$prompt". Reply with ONLY the title, no quotes.',
            },
          ],
          'max_tokens': 20,
          'temperature': 0.3,
        },
        timeout: const Duration(seconds: 90),
      );
      if (resp.statusCode != 200) return '$typeLabel Exam';
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['choices'][0]['message']['content'] as String).trim();
    } catch (_) {
      return '${_typeLabel(type)} Exam';
    }
  }

  Future<ExamGenerationResult> _runCreationHarness({
    required ExamGenerationResult draft,
    required String model,
    required String prompt,
    required String type,
    required int questionCount,
    required String difficulty,
    required int mcqOptionCount,
    String? subjectName,
    required String contextBlock,
  }) async {
    var current = draft;

    for (var pass = 2; pass <= _creationHarnessPasses; pass++) {
      try {
        final currentJson = _questionsToJson(current.title, current.questions);
        final system =
            '''You are pass $pass in an exam creation harness${subjectName != null ? ' for $subjectName' : ''}.
Validate and improve the current exam against the original request.
Return ONLY a valid JSON object with the COMPLETE exam.

REQUIREMENTS:
- Exactly $questionCount questions
- Difficulty: $difficulty
- ${_typeInstruction(type, mcqOptionCount)}
- Every question must have a correctAnswer and explanation
- Use the provided study material as the primary source when available

${contextBlock.isEmpty ? '' : 'STUDY MATERIAL:\n$contextBlock\n\n'}CURRENT EXAM:
$currentJson''';

        final resp = await AIBackendService.postChatCompletions(
          payload: {
            'model': model,
            'messages': [
              {'role': 'system', 'content': system},
              {
                'role': 'user',
                'content':
                    'Original request: ${prompt.trim().isEmpty ? 'Generate $questionCount questions.' : prompt}\nCreate the next improved complete exam draft.',
              },
            ],
            if (contextBlock.isNotEmpty) 'contexts': [contextBlock],
            'temperature': 0.35,
            'max_tokens': 5000,
            'response_format': {'type': 'json_object'},
          },
          timeout: const Duration(seconds: 120),
        );
        if (resp.statusCode != 200) break;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final content = data['choices'][0]['message']['content'] as String;
        await _logUsage(data, 'exam_generate_harness');
        current = _parseResponse(content, current.title, type);
      } catch (_) {
        break;
      }
    }

    return current;
  }

  // ── Prompt builders ──────────────────────────────────────────────────────

  String _buildGenerationSystemPrompt({
    required String type,
    required int questionCount,
    required String difficulty,
    required int mcqOptionCount,
    String? subjectName,
    String contextBlock = '',
  }) {
    final typeInstruction = _typeInstruction(type, mcqOptionCount);
    final context = contextBlock.isEmpty
        ? ''
        : '\n\nUse this study material as the primary source:\n$contextBlock';

    return '''You are an expert exam creator${subjectName != null ? ' for $subjectName' : ''}.
Generate exactly $questionCount questions. Difficulty: $difficulty.
$typeInstruction$context

CRITICAL: Return ONLY a valid JSON object — no extra text, no markdown, no code block. Use this exact structure:
{
  "title": "Concise descriptive exam title (5-8 words)",
  "questions": [
    {
      "id": "1",
      "type": "mcq",
      "question": "Clear, well-phrased question text",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctAnswer": "Option A",
      "explanation": "Brief explanation of why this answer is correct (1-2 sentences)"
    }
  ]
}

For fill_blank questions, put ___ in the question text for each blank.
For short_answer and long_answer, omit "options". "correctAnswer" is the expected answer.
For true_false, options MUST be exactly ["True", "False"].
For mixed type, vary the question types across the list.
Every question MUST have an "explanation" field.''';
  }

  String _buildEditSystemPrompt({
    required String examType,
    String? subjectName,
    String contextBlock = '',
    required String currentExamJson,
  }) {
    final context = contextBlock.isEmpty
        ? ''
        : '\n\nAdditional study material:\n$contextBlock';

    return '''You are an exam editor${subjectName != null ? ' for $subjectName' : ''}.
You are helping refine an existing $examType exam.$context

CRITICAL: Return ONLY a valid JSON object with the COMPLETE updated exam (ALL questions — modified, added, and unchanged). Same format as before:
{
  "title": "Updated title if relevant",
  "questions": [ ... complete list ... ]
}

When adding questions, continue numbering. When removing or replacing, re-index from 1.
Preserve explanations for unchanged questions.

CURRENT EXAM:
$currentExamJson''';
  }

  String _typeInstruction(String type, int mcqOptionCount) => switch (type) {
    'mcq' =>
      'Generate multiple-choice questions with exactly $mcqOptionCount options each. The correctAnswer must EXACTLY match one of the options.',
    'true_false' =>
      'Generate true-or-false questions. options MUST be ["True", "False"] for every question. correctAnswer is "True" or "False".',
    'fill_blank' =>
      'Generate fill-in-the-blank questions. Use ___ in the question for each blank. Do not include options.',
    'short_answer' =>
      'Generate short-answer questions. No options. The correctAnswer is a 1-3 sentence response.',
    'long_answer' =>
      'Generate long-answer / essay questions. No options. The correctAnswer is a detailed multi-sentence response.',
    'mixed' =>
      'Generate a mix of question types (mcq, true_false, fill_blank, short_answer). Vary them throughout. Each question must have its "type" field set correctly.',
    _ => 'Generate questions appropriate for the topic.',
  };

  // ── Context builder ──────────────────────────────────────────────────────

  Future<String> _buildContextBlock(
    List<String> chapterIds,
    String query,
  ) async {
    if (chapterIds.isEmpty) return '';
    try {
      final retrieval = RetrievalService(_chunkRepo);
      final chunks = <String>[];
      for (final cid in chapterIds) {
        final found = await retrieval.searchChapter(
          cid,
          query.isEmpty ? 'overview' : query,
        );
        chunks.addAll(found.map((c) => c.text));
      }
      if (chunks.isEmpty) return '';
      return chunks.take(8).join('\n\n');
    } catch (_) {
      return '';
    }
  }

  // ── JSON parsing ─────────────────────────────────────────────────────────

  ExamGenerationResult _parseResponse(
    String raw,
    String fallbackTitle,
    String fallbackType,
  ) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Try to extract JSON block if there's surrounding text
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (match == null) {
        throw AppException.service(
          'Could not parse exam response. Please try again.',
        );
      }
      try {
        json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      } catch (_) {
        throw AppException.service(
          'Invalid exam format returned. Please try again.',
        );
      }
    }

    final title = (json['title'] as String?)?.trim() ?? fallbackTitle;
    final rawQuestions = json['questions'] as List<dynamic>? ?? [];

    if (rawQuestions.isEmpty) {
      throw AppException.service(
        'No questions were generated. Try a different prompt.',
      );
    }

    final questions = rawQuestions.asMap().entries.map((entry) {
      final i = entry.key;
      final q = entry.value as Map<String, dynamic>;

      final qType = (q['type'] as String?)?.trim() ?? fallbackType;
      List<String>? options;
      final rawOpts = q['options'] as List<dynamic>?;
      if (rawOpts != null) {
        options = rawOpts.cast<String>();
      }

      return ExamQuestion(
        id: const Uuid().v4(),
        examId: '', // filled by caller
        questionIndex: i,
        type: qType,
        question: (q['question'] as String?)?.trim() ?? '',
        options: options,
        correctAnswer: (q['correctAnswer'] as String?)?.trim() ?? '',
        explanation: (q['explanation'] as String?)?.trim(),
      );
    }).toList();

    return ExamGenerationResult(title: title, questions: questions);
  }

  String _questionsToJson(String title, List<ExamQuestion> questions) {
    final list = questions
        .map(
          (q) => {
            'id': '${q.questionIndex + 1}',
            'type': q.type,
            'question': q.question,
            if (q.options != null) 'options': q.options,
            'correctAnswer': q.correctAnswer,
            if (q.explanation != null) 'explanation': q.explanation,
          },
        )
        .toList();
    return jsonEncode({'title': title, 'questions': list});
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildUserMsg(String content, String? imagePath) {
    if (imagePath == null) return {'role': 'user', 'content': content};
    try {
      final bytes = File(imagePath).readAsBytesSync();
      final b64 = base64Encode(bytes);
      final ext = imagePath.split('.').last.toLowerCase();
      final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
      return {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': content},
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mime;base64,$b64', 'detail': 'auto'},
          },
        ],
      };
    } catch (_) {
      return {'role': 'user', 'content': content};
    }
  }

  Future<void> _logUsage(
    Map<String, dynamic> responseData,
    String toolType,
  ) async {
    try {
      final usage = responseData['usage'] as Map<String, dynamic>?;
      final inTok = (usage?['prompt_tokens'] as int?) ?? 0;
      final outTok = (usage?['completion_tokens'] as int?) ?? 0;
      final inPrice =
          double.tryParse(
            await _settingsRepo.get(SettingKeys.inputTokenPrice) ?? '',
          ) ??
          _defaultInputPrice;
      final outPrice =
          double.tryParse(
            await _settingsRepo.get(SettingKeys.outputTokenPrice) ?? '',
          ) ??
          _defaultOutputPrice;
      final cost = (inTok / 1000) * inPrice + (outTok / 1000) * outPrice;
      await _usageRepo.insert(
        UsageLog(
          id: const Uuid().v4(),
          toolType: toolType,
          inputTokensEstimate: inTok,
          outputTokensEstimate: outTok,
          estimatedCost: cost,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {}
  }

  String _typeLabel(String type) => switch (type) {
    'mcq' => 'MCQ',
    'true_false' => 'True/False',
    'fill_blank' => 'Fill-in-Blank',
    'short_answer' => 'Short Answer',
    'long_answer' => 'Long Answer',
    'mixed' => 'Mixed',
    _ => 'Exam',
  };

  AppException _buildException(http.Response r) {
    var msg = 'Unexpected error from the backend.';
    try {
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      msg = d['error']?['message'] as String? ?? msg;
    } catch (_) {}
    if (r.statusCode == 401 || r.statusCode == 403) {
      return AppException.authentication('Sign in again and retry.');
    }
    if (r.statusCode == 429) return AppException.rateLimit(msg);
    return AppException.service(msg);
  }
}
