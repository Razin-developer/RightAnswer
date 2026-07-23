import '../models/study_day.dart';
import '../models/study_plan.dart';
import '../models/study_task.dart';
import '../repositories/study_day_repository.dart';
import '../repositories/study_plan_repository.dart';
import '../repositories/study_task_repository.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'connectivity_service.dart';

/// Mirrors study plans (days + tasks) to Postgres — see ExamSyncService's
/// doc comment for why this exists and the same best-effort/never-blocks
/// contract.
class StudyPlanSyncService {
  static final StudyPlanSyncService instance = StudyPlanSyncService._();
  StudyPlanSyncService._();

  final _planRepo = StudyPlanRepository();
  final _dayRepo = StudyDayRepository();
  final _taskRepo = StudyTaskRepository();

  bool get _ready =>
      AuthService.instance.isLoggedIn && ConnectivityService.instance.isOnline;

  Future<void> pushPlan(String planId) async {
    if (!_ready) return;
    try {
      final plan = await _planRepo.getById(planId);
      if (plan == null) return;
      final days = await _dayRepo.getByPlan(planId);
      final tasks = await _taskRepo.getByPlan(planId);
      await ApiService.instance.put('/api/study-plans/by-local/${plan.id}', {
        'name': plan.name,
        'data': {
          'plan': plan.toMap(),
          'days': days.map((d) => d.toMap()).toList(),
          'tasks': tasks.map((t) => t.toMap()).toList(),
        },
      });
    } catch (_) {
      // Best-effort — the local save already succeeded regardless.
    }
  }

  Future<void> deletePlan(String planId) async {
    if (!_ready) return;
    try {
      await ApiService.instance.delete('/api/study-plans/by-local/$planId');
    } catch (_) {}
  }

  /// Pulls plans that exist on the server but not locally — never
  /// overwrites a local plan that already exists.
  Future<void> pullMissing() async {
    if (!_ready) return;
    try {
      final response = await ApiService.instance.get('/api/study-plans');
      final raw = response['studyPlans'];
      if (raw is! List) return;

      for (final entry in raw) {
        if (entry is! Map) continue;
        final data = entry['data'];
        if (data is! Map) continue;
        final planMap = data['plan'];
        if (planMap is! Map) continue;

        final plan = StudyPlan.fromMap(
          planMap.map((k, v) => MapEntry(k.toString(), v)),
        );
        final existing = await _planRepo.getById(plan.id);
        if (existing != null) continue;

        await _planRepo.insert(plan);
        final rawDays = data['days'];
        if (rawDays is List) {
          for (final d in rawDays) {
            if (d is! Map) continue;
            await _dayRepo.insert(
              StudyDay.fromMap(d.map((k, v) => MapEntry(k.toString(), v))),
            );
          }
        }
        final rawTasks = data['tasks'];
        if (rawTasks is List) {
          for (final t in rawTasks) {
            if (t is! Map) continue;
            await _taskRepo.insert(
              StudyTask.fromMap(t.map((k, v) => MapEntry(k.toString(), v))),
            );
          }
        }
      }
    } catch (_) {
      // Offline, timed out, or backend error — retry on next app launch.
    }
  }
}
