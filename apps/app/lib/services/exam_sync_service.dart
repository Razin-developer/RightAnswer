import '../models/exam.dart';
import '../models/exam_question.dart';
import '../repositories/exam_question_repository.dart';
import '../repositories/exam_repository.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

/// Mirrors exams (and their questions) to Postgres — previously exams
/// only ever existed in the device's local SQLite, so uninstalling the
/// app or switching devices lost them permanently. Push is best-effort and
/// fire-and-forget from the caller's perspective: a failed sync never
/// blocks or breaks the local save, exactly like CloudSyncService's chat
/// sync.
class ExamSyncService {
  static final ExamSyncService instance = ExamSyncService._();
  ExamSyncService._();

  final _examRepo = ExamRepository();
  final _questionRepo = ExamQuestionRepository();

  bool get _ready =>
      AuthService.instance.isLoggedIn && ConnectivityService.instance.isOnline;

  Future<void> pushExam(String examId) async {
    if (!_ready) return;
    try {
      final exam = await _examRepo.getById(examId);
      if (exam == null) return;
      final questions = await _questionRepo.getByExam(examId);
      await ApiService.instance.put('/api/exams/by-local/${exam.id}', {
        'name': exam.name,
        'data': {
          'exam': exam.toMap(),
          'questions': questions.map((q) => q.toMap()).toList(),
        },
      });
    } catch (_) {
      // Best-effort — the local save already succeeded regardless.
    }
  }

  Future<void> deleteExam(String examId) async {
    if (!_ready) return;
    try {
      await ApiService.instance.delete('/api/exams/by-local/$examId');
    } catch (_) {}
  }

  /// Pulls exams that exist on the server but not locally (e.g. after a
  /// reinstall or on a new device) — never overwrites a local exam that
  /// already exists, since the user may have unsynced local edits.
  Future<void> pullMissing() async {
    if (!_ready) return;
    try {
      final response = await ApiService.instance.get('/api/exams');
      final raw = response['exams'];
      if (raw is! List) return;

      for (final entry in raw) {
        if (entry is! Map) continue;
        final data = entry['data'];
        if (data is! Map) continue;
        final examMap = data['exam'];
        if (examMap is! Map) continue;

        final exam = Exam.fromMap(
          examMap.map((k, v) => MapEntry(k.toString(), v)),
        );
        final existing = await _examRepo.getById(exam.id);
        if (existing != null) continue;

        await _examRepo.insert(exam);
        final rawQuestions = data['questions'];
        if (rawQuestions is! List) continue;
        for (final q in rawQuestions) {
          if (q is! Map) continue;
          await _questionRepo.insert(
            ExamQuestion.fromMap(q.map((k, v) => MapEntry(k.toString(), v))),
          );
        }
      }
    } catch (_) {
      // Offline, timed out, or backend error — retry on next app launch.
    }
  }
}
