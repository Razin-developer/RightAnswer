import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/app_exception.dart';
import '../models/beta_confirmation_exception.dart';
import '../models/usage_log.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import 'ai_backend_service.dart';

// ── Draft models (pre-save) ────────────────────────────────────────────────────

class StudyTaskDraft {
  String title;
  String description;
  final String? chapterId;
  final String? chapterName;
  int durationMinutes;

  StudyTaskDraft({
    required this.title,
    required this.description,
    this.chapterId,
    this.chapterName,
    required this.durationMinutes,
  });
}

class StudyDayDraft {
  final DateTime date;
  List<StudyTaskDraft> tasks;

  StudyDayDraft({required this.date, required this.tasks});
}

class StudyPlanDraft {
  String suggestedName;
  final List<StudyDayDraft> days;

  StudyPlanDraft({required this.suggestedName, required this.days});
}

// ── Service ────────────────────────────────────────────────────────────────────

class StudyPlanAIService {
  static final StudyPlanAIService instance = StudyPlanAIService._();
  StudyPlanAIService._();

  final _settingsRepo = SettingsRepository();
  final _usageRepo = UsageLogRepository();

  static const _defaultInputPrice = 0.0005;
  static const _defaultOutputPrice = 0.0015;
  static const _creationHarnessPasses = 4;

  static const _dayNames = {
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  Future<StudyPlanDraft> generatePlan({
    required String planName,
    required DateTime examDate,
    required DateTime startDate,
    required List<int> freeDays,
    required double hoursPerDay,
    String? topic,
    // Optional — only set when the user picked a chapter via the chapter
    // picker. Scopes backend Qdrant retrieval to just this chapter; null or
    // empty preserves the existing global-search behavior.
    List<String>? chapterIds,
    // Set when the user tapped "Yes" on the beta-chapter confirmation
    // dialog for a previous attempt — see BetaConfirmationRequiredException
    // and study_plan_create_screen.dart's confirmation flow.
    String? confirmBetaChapterId,
  }) async {
    AIBackendService.requireChatApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    final freeDayNames = freeDays
        .map((d) => _dayNames[d] ?? '')
        .where((s) => s.isNotEmpty)
        .join(', ');

    final startStr = _fmt(startDate);
    final examStr = _fmt(examDate);
    final hInt = hoursPerDay.toInt();
    final hMin = ((hoursPerDay - hInt) * 60).toInt();
    final hoursLabel = hMin == 0 ? '${hInt}h' : '${hInt}h ${hMin}m';

    final system =
        '''You are an expert study planner. Create a day-by-day study plan.

CONSTRAINTS:
- Study period: $startStr to $examStr (exclusive — last study day is the day BEFORE the exam)
- Free days (skip entirely): ${freeDayNames.isEmpty ? 'none' : freeDayNames}
- Study time per day: $hoursLabel
- What to study: ${topic != null && topic.trim().isNotEmpty ? topic.trim() : 'General — infer reasonable topics from the plan name "$planName"'}

RULES:
- Only include actual study days (not free days, not the exam day itself)
- Each task must have a clear, specific title (what to study)
- Task durations must be in 30-minute increments (30, 60, 90, 120)
- Sum of durations in a day ≈ available study time
- Spread topics evenly; don't front-load or back-load
- Last 20 % of days: include revision/review tasks

Return ONLY valid JSON — no markdown, no explanation:
{
  "planName": "Concise title (5-7 words)",
  "days": [
    {
      "date": "YYYY-MM-DD",
      "tasks": [
        {
          "title": "Task title",
          "description": "What to focus on and key goals",
          "chapterName": "Topic name",
          "durationMinutes": 60
        }
      ]
    }
  ]
}''';

    final resp = await AIBackendService.postChatCompletions(
      payload: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': 'Generate my study plan for: $planName'},
        ],
        'temperature': 0.4,
        'max_tokens': 6000,
        'response_format': {'type': 'json_object'},
        if (chapterIds != null && chapterIds.isNotEmpty)
          'chapterIds': chapterIds,
        'confirmBetaChapterId': ?confirmBetaChapterId,
      },
      timeout: const Duration(seconds: 120),
    );
    if (resp.statusCode != 200) throw _buildException(resp);

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final betaConfirmation = BetaConfirmationRequiredException.fromResponse(
      data,
    );
    if (betaConfirmation != null) throw betaConfirmation;

    await _logUsage(data, 'study_plan_generate');
    final draft = _parse(data['choices'][0]['message']['content'] as String);
    return _runCreationHarness(
      draft: draft,
      originalConstraints: system,
      model: model,
      chapterIds: chapterIds,
    );
  }

  Future<StudyPlanDraft> refinePlan({
    required StudyPlanDraft current,
    required String instruction,
    String? confirmBetaChapterId,
  }) async {
    AIBackendService.requireChatApiKey();
    final model =
        await _settingsRepo.get(SettingKeys.openAiModel) ?? 'gpt-4o-mini';

    final system =
        '''You are a study plan editor. Modify the plan based on the user's instruction.

Return the COMPLETE updated plan in identical JSON format:
{
  "planName": "...",
  "days": [...]
}

CURRENT PLAN:
${_draftToJson(current)}''';

    final resp = await AIBackendService.postChatCompletions(
      payload: {
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': instruction},
        ],
        'temperature': 0.4,
        'max_tokens': 6000,
        'response_format': {'type': 'json_object'},
        'confirmBetaChapterId': ?confirmBetaChapterId,
      },
      timeout: const Duration(seconds: 120),
    );
    if (resp.statusCode != 200) throw _buildException(resp);

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final betaConfirmation = BetaConfirmationRequiredException.fromResponse(
      data,
    );
    if (betaConfirmation != null) throw betaConfirmation;

    await _logUsage(data, 'study_plan_refine');
    return _parse(data['choices'][0]['message']['content'] as String);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<StudyPlanDraft> _runCreationHarness({
    required StudyPlanDraft draft,
    required String originalConstraints,
    required String model,
    List<String>? chapterIds,
  }) async {
    var current = draft;

    for (var pass = 2; pass <= _creationHarnessPasses; pass++) {
      try {
        final system =
            '''You are pass $pass in a study-plan creation harness.
Validate the current draft against the original constraints, fix gaps, improve balance, and make tasks more specific.
Return ONLY the COMPLETE updated JSON in the same schema.

ORIGINAL CONSTRAINTS:
$originalConstraints

CURRENT DRAFT:
${_draftToJson(current)}''';

        final resp = await AIBackendService.postChatCompletions(
          payload: {
            'model': model,
            'messages': [
              {'role': 'system', 'content': system},
              {
                'role': 'user',
                'content':
                    'Create the next improved complete study-plan draft.',
              },
            ],
            'temperature': 0.35,
            'max_tokens': 6000,
            'response_format': {'type': 'json_object'},
            if (chapterIds != null && chapterIds.isNotEmpty)
              'chapterIds': chapterIds,
          },
          timeout: const Duration(seconds: 120),
        );
        if (resp.statusCode != 200) break;

        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        await _logUsage(data, 'study_plan_harness');
        current = _parse(data['choices'][0]['message']['content'] as String);
      } catch (_) {
        break;
      }
    }

    return current;
  }

  StudyPlanDraft _parse(String raw) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      final m = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (m == null) {
        throw AppException.service(
          'Could not parse study plan. Please try again.',
        );
      }
      json = jsonDecode(m.group(0)!) as Map<String, dynamic>;
    }

    final name = (json['planName'] as String?)?.trim() ?? 'Study Plan';
    final rawDays = json['days'] as List<dynamic>? ?? [];

    final days = rawDays.map((d) {
      final dm = d as Map<String, dynamic>;
      DateTime date;
      try {
        date = DateTime.parse(dm['date'] as String? ?? '');
      } catch (_) {
        date = DateTime.now();
      }

      final rawTasks = dm['tasks'] as List<dynamic>? ?? [];
      final tasks = rawTasks.asMap().entries.map((e) {
        final tm = e.value as Map<String, dynamic>;
        final cid = tm['chapterId'] as String?;
        return StudyTaskDraft(
          title: (tm['title'] as String?)?.trim() ?? 'Study session',
          description: (tm['description'] as String?)?.trim() ?? '',
          chapterId: (cid == null || cid == 'null' || cid.isEmpty) ? null : cid,
          chapterName: (tm['chapterName'] as String?)?.trim(),
          durationMinutes: (tm['durationMinutes'] as int?) ?? 60,
        );
      }).toList();

      return StudyDayDraft(date: date, tasks: tasks);
    }).toList();

    return StudyPlanDraft(suggestedName: name, days: days);
  }

  String _draftToJson(StudyPlanDraft draft) {
    final days = draft.days
        .map(
          (d) => {
            'date': _fmt(d.date),
            'tasks': d.tasks
                .map(
                  (t) => {
                    'title': t.title,
                    'description': t.description,
                    if (t.chapterId != null) 'chapterId': t.chapterId,
                    'chapterName': t.chapterName ?? '',
                    'durationMinutes': t.durationMinutes,
                  },
                )
                .toList(),
          },
        )
        .toList();
    return jsonEncode({'planName': draft.suggestedName, 'days': days});
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _logUsage(Map<String, dynamic> data, String tool) async {
    try {
      final usage = data['usage'] as Map<String, dynamic>?;
      final inTok = (usage?['prompt_tokens'] as int?) ?? 0;
      final outTok = (usage?['completion_tokens'] as int?) ?? 0;
      final inP =
          double.tryParse(
            await _settingsRepo.get(SettingKeys.inputTokenPrice) ?? '',
          ) ??
          _defaultInputPrice;
      final outP =
          double.tryParse(
            await _settingsRepo.get(SettingKeys.outputTokenPrice) ?? '',
          ) ??
          _defaultOutputPrice;
      await _usageRepo.insert(
        UsageLog(
          id: const Uuid().v4(),
          toolType: tool,
          inputTokensEstimate: inTok,
          outputTokensEstimate: outTok,
          estimatedCost: (inTok / 1000) * inP + (outTok / 1000) * outP,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {}
  }

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
