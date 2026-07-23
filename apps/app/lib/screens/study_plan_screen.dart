import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/study_plan.dart';
import '../models/study_task.dart';
import '../repositories/study_day_repository.dart';
import '../repositories/study_plan_repository.dart';
import '../repositories/study_task_repository.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/import_export_service.dart';
import '../services/notification_service.dart';
import '../services/study_plan_sync_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/plan_gate.dart';
import 'study_plan_create_screen.dart';
import 'study_plan_detail_screen.dart';

const _coral = Color(0xFFCC785C);

class StudyPlanScreen extends StatefulWidget {
  final String? initialPlanId;

  const StudyPlanScreen({super.key, this.initialPlanId});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  final _planRepo = StudyPlanRepository();
  final _dayRepo = StudyDayRepository();
  final _taskRepo = StudyTaskRepository();

  List<StudyPlan> _plans = [];
  final Map<String, (int, int)> _progress = {};
  List<StudyTask> _todayTasks = [];
  String? _todayPlanId;
  bool _loading = true;
  bool _sharingLink = false;
  bool _didConsumeInitialPlan = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plans = await _planRepo.getAll();
    final progress = <String, (int, int)>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    List<StudyTask> todayTasks = [];
    String? todayPlanId;

    for (final p in plans) {
      final total = await _taskRepo.countTotal(p.id);
      final completed = await _taskRepo.countCompleted(p.id);
      progress[p.id] = (completed, total);

      if (p.isActive && todayTasks.isEmpty) {
        final days = await _dayRepo.getByPlan(p.id);
        for (final d in days) {
          final dDate = DateTime(d.date.year, d.date.month, d.date.day);
          if (dDate == today) {
            todayTasks = await _taskRepo.getByDay(d.id);
            todayPlanId = p.id;
            break;
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _plans = plans;
        _progress.addAll(progress);
        _todayTasks = todayTasks;
        _todayPlanId = todayPlanId;
        _loading = false;
      });
    }

    final initialPlanId = widget.initialPlanId;
    if (_didConsumeInitialPlan || initialPlanId == null) {
      return;
    }

    _didConsumeInitialPlan = true;
    final plan = plans.where((item) => item.id == initialPlanId).firstOrNull;
    if (plan == null || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openDetail(plan);
      }
    });
  }

  Future<void> _deletePlan(StudyPlan plan) async {
    final confirmed = await AppFeedback.confirmDelete(
      context,
      title: Text(
        'Delete "${plan.name}"?',
        style: GoogleFonts.playfairDisplay(fontSize: 18),
      ),
      content: const Text(
        'This will permanently delete the plan and all its tasks.',
      ),
      accentColor: const Color(0xFFC64545),
    );
    if (!confirmed) return;
    if (plan.hasReminder) {
      await NotificationService.instance.cancelStudyPlanReminder(plan.id);
    }
    await _taskRepo.deleteByPlan(plan.id);
    await _dayRepo.deleteByPlan(plan.id);
    await _planRepo.delete(plan.id);
    unawaited(StudyPlanSyncService.instance.deletePlan(plan.id));
    if (mounted) _load();
  }

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudyPlanCreateScreen()),
    );
    _load();
  }

  Future<void> _openDetail(StudyPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudyPlanDetailScreen(planId: plan.id)),
    );
    _load();
  }

  Future<void> _openEdit(StudyPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyPlanCreateScreen(existingPlan: plan),
      ),
    );
    _load();
  }

  Future<void> _sharePlan(StudyPlan plan) async {
    if (!AuthService.instance.isLoggedIn) {
      AppFeedback.showToast(context, 'Sign in to share study plans');
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(context, 'You are offline');
      return;
    }

    setState(() => _sharingLink = true);
    try {
      final bytes = await ImportExportService.instance.exportStudyPlanToBytes(
        plan.id,
      );
      final result = await CloudSyncService.instance.uploadContentZip(
        bytes: bytes,
        metadata: {'type': 'study-plan', 'name': plan.name},
      );
      final url = result['url'] as String? ?? '';
      if (mounted) _showLinkDialog('Share Study Plan', url);
    } catch (e) {
      if (mounted) AppFeedback.showToast(context, 'Failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _sharingLink = false);
    }
  }

  void _showLinkDialog(String title, String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this link to let others import it.\nExpires in 10 minutes.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              AppFeedback.showToast(context, 'Link copied');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plan = AuthService.instance.currentUser?.plan ?? 'hobby';
    if (plan == 'hobby') {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            'Study Plans',
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              letterSpacing: -0.3,
            ),
          ),
          centerTitle: false,
        ),
        body: const PlanGate(
          featureName: 'Study Plans',
          description:
              'Personalized study schedules are available on Pro and Scholar. Upgrade to build a plan for your exams.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Study Plans',
          style: GoogleFonts.playfairDisplay(fontSize: 20, letterSpacing: -0.3),
        ),
        centerTitle: false,
        actions: [
          if (_sharingLink)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
          ? _EmptyState(onAdd: _openCreate)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (_todayTasks.isNotEmpty) ...[
                    _TodayCard(
                      tasks: _todayTasks,
                      isDark: isDark,
                      onTap: () {
                        final plan = _plans.firstWhere(
                          (p) => p.id == _todayPlanId,
                          orElse: () => _plans.first,
                        );
                        _openDetail(plan);
                      },
                    ),
                    const SizedBox(height: 20),
                    _SectionLabel('All Plans', isDark: isDark),
                    const SizedBox(height: 8),
                  ],
                  for (final plan in _plans)
                    _PlanCard(
                      plan: plan,
                      progress: _progress[plan.id] ?? (0, 0),
                      isDark: isDark,
                      onTap: () => _openDetail(plan),
                      onEdit: () => _openEdit(plan),
                      onShare: () => _sharePlan(plan),
                      onDelete: () => _deletePlan(plan),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: _coral,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'New Plan',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        elevation: 2,
      ),
    );
  }
}

// ── Today's Focus Card ────────────────────────────────────────────────────────

class _TodayCard extends StatelessWidget {
  final List<StudyTask> tasks;
  final bool isDark;
  final VoidCallback onTap;

  const _TodayCard({
    required this.tasks,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where((t) => t.isCompleted).length;
    final total = tasks.length;
    final allDone = completed == total;
    final next = tasks.firstWhere(
      (t) => !t.isCompleted,
      orElse: () => tasks.first,
    );
    final totalMin = tasks.fold(0, (s, t) => s + t.durationMinutes);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: allDone
              ? const Color(0xFF5DB872).withValues(alpha: 0.08)
              : _coral.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: allDone
                ? const Color(0xFF5DB872).withValues(alpha: 0.3)
                : _coral.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  allDone ? '✦ All done today!' : '✦ Today',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: allDone ? const Color(0xFF5DB872) : _coral,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '$completed/$total tasks · ${_fmtMin(totalMin)}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF8E8B82)
                        : const Color(0xFF6C6A64),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!allDone) ...[
              Text(
                next.title,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 17,
                  color: isDark
                      ? const Color(0xFFFAF9F5)
                      : const Color(0xFF141413),
                  letterSpacing: -0.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (next.chapterName != null) ...[
                const SizedBox(height: 4),
                Text(
                  next.chapterName!,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF8E8B82)
                        : const Color(0xFF6C6A64),
                  ),
                ),
              ],
            ] else
              Text(
                'Great work! You finished all tasks for today.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF5DB872),
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : completed / total,
                minHeight: 4,
                backgroundColor: isDark
                    ? const Color(0xFF2E2C28)
                    : const Color(0xFFE6DFD8),
                valueColor: AlwaysStoppedAnimation(
                  allDone ? const Color(0xFF5DB872) : _coral,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  allDone ? 'View review' : 'Continue studying',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: allDone ? const Color(0xFF5DB872) : _coral,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: allDone ? const Color(0xFF5DB872) : _coral,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmtMin(int min) {
    if (min < 60) return '${min}m';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ── Plan Card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  final StudyPlan plan;
  final (int, int) progress;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _PlanCard({
    required this.plan,
    required this.progress,
    required this.isDark,
    required this.onTap,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final (completed, total) = progress;
    final pct = total == 0 ? 0.0 : completed / total;
    final cardBg = isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFFFEFC);
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final textColor = isDark
        ? const Color(0xFFFAF9F5)
        : const Color(0xFF141413);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    final statusColor = switch (plan.status) {
      'completed' => const Color(0xFF5DB872),
      'paused' => const Color(0xFFE8A55A),
      _ => _coral,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 15,
                          color: textColor,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _StatusChip(
                            label:
                                plan.status[0].toUpperCase() +
                                plan.status.substring(1),
                            color: statusColor,
                          ),
                          if (plan.subjectName != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              plan.subjectName!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: muted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: muted, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'share') onShare();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 16),
                          const SizedBox(width: 8),
                          Text('Edit', style: GoogleFonts.inter(fontSize: 14)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          const Icon(Icons.ios_share_outlined, size: 16),
                          const SizedBox(width: 8),
                          Text('Share', style: GoogleFonts.inter(fontSize: 14)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 16,
                            color: Color(0xFFC64545),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Delete',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: const Color(0xFFC64545),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                backgroundColor: isDark
                    ? const Color(0xFF2E2C28)
                    : const Color(0xFFE6DFD8),
                valueColor: AlwaysStoppedAnimation(
                  pct == 1.0 ? const Color(0xFF5DB872) : _coral,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 13,
                  color: muted,
                ),
                const SizedBox(width: 4),
                Text(
                  '$completed/$total tasks',
                  style: GoogleFonts.inter(fontSize: 11, color: muted),
                ),
                const SizedBox(width: 12),
                Icon(Icons.calendar_today_outlined, size: 13, color: muted),
                const SizedBox(width: 4),
                Text(
                  _daysLabel(plan),
                  style: GoogleFonts.inter(fontSize: 11, color: muted),
                ),
                if (plan.hasReminder) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.notifications_outlined,
                    size: 13,
                    color: _coral.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${plan.reminderHour!.toString().padLeft(2, '0')}:${plan.reminderMinute!.toString().padLeft(2, '0')}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _coral.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _daysLabel(StudyPlan p) {
    final d = p.daysToExam;
    if (d < 0) return 'Exam passed';
    if (d == 0) return 'Exam today!';
    return '$d days to exam';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9999),
    ),
    child: Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionLabel(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64),
    ),
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFFFAF9F5)
        : const Color(0xFF141413);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '✦',
              style: GoogleFonts.inter(
                fontSize: 36,
                color: _coral,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No study plans yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.3,
                color: textColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Create an AI-powered study plan tailored\nto your exam date and chapters.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: muted, height: 1.6),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: _coral,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Create Plan',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
