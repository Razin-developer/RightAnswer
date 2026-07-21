import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/study_day.dart';
import '../models/study_plan.dart';
import '../models/study_task.dart';
import '../repositories/study_day_repository.dart';
import '../repositories/study_plan_repository.dart';
import '../repositories/study_task_repository.dart';
import '../widgets/app_feedback.dart';
import 'study_plan_create_screen.dart';

const _coral = Color(0xFFCC785C);

class StudyPlanDetailScreen extends StatefulWidget {
  final String planId;

  const StudyPlanDetailScreen({super.key, required this.planId});

  @override
  State<StudyPlanDetailScreen> createState() => _StudyPlanDetailScreenState();
}

class _StudyPlanDetailScreenState extends State<StudyPlanDetailScreen> {
  final _planRepo = StudyPlanRepository();
  final _dayRepo = StudyDayRepository();
  final _taskRepo = StudyTaskRepository();

  StudyPlan? _plan;
  List<StudyDay> _days = [];
  final Map<String, List<StudyTask>> _tasksByDay = {};
  bool _loading = true;

  // Expanded days set
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plan = await _planRepo.getById(widget.planId);
    if (plan == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final days = await _dayRepo.getByPlan(plan.id);
    final tasksByDay = <String, List<StudyTask>>{};
    for (final d in days) {
      tasksByDay[d.id] = await _taskRepo.getByDay(d.id);
    }

    // Auto-expand today
    for (final d in days) {
      if (d.isToday) _expanded.add(d.id);
    }

    if (mounted) {
      setState(() {
        _plan = plan;
        _days = days;
        _tasksByDay.addAll(tasksByDay);
        _loading = false;
      });
    }
  }

  // ── Progress metrics ───────────────────────────────────────────────────────

  int get _totalTasks =>
      _tasksByDay.values.fold(0, (s, list) => s + list.length);

  int get _completedTasks =>
      _tasksByDay.values.fold(0, (s, list) => s + list.where((t) => t.isCompleted).length);

  int get _completedDays => _days.where((d) => d.isCompleted).length;

  double get _progress =>
      _totalTasks == 0 ? 0 : _completedTasks / _totalTasks;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _toggleTask(StudyDay day, StudyTask task) async {
    final updated = task.copyWith(
      isCompleted: !task.isCompleted,
      completedAt: !task.isCompleted ? DateTime.now() : null,
    );
    await _taskRepo.update(updated);

    // Check if all tasks in this day are done → auto-complete the day
    final dayTasks = _tasksByDay[day.id] ?? [];
    final updatedList =
        dayTasks.map((t) => t.id == task.id ? updated : t).toList();
    final allDone = updatedList.isNotEmpty && updatedList.every((t) => t.isCompleted);
    if (allDone != day.isCompleted) {
      final updatedDay = day.copyWith(isCompleted: allDone);
      await _dayRepo.update(updatedDay);
    }

    // Check if entire plan is done
    final totalCount = _tasksByDay.values.fold(0, (s, l) => s + l.length);
    final doneCount = _tasksByDay.values
        .fold(0, (s, l) => s + l.where((t) => t.isCompleted).length) +
        (updated.isCompleted ? 1 : -1);

    if (totalCount > 0 && doneCount == totalCount && _plan!.status == 'active') {
      await _planRepo.updateStatus(widget.planId, 'completed');
    }

    _load();
  }

  Future<void> _toggleStatus() async {
    final plan = _plan;
    if (plan == null) return;
    final newStatus = plan.isActive ? 'paused' : 'active';
    await _planRepo.updateStatus(plan.id, newStatus);
    if (mounted) {
      AppFeedback.showToast(
          context, newStatus == 'active' ? 'Plan resumed' : 'Plan paused');
      _load();
    }
  }

  Future<void> _editPlan() async {
    final nav = Navigator.of(context);
    await nav.push(MaterialPageRoute(
        builder: (_) => StudyPlanCreateScreen(existingPlan: _plan)));
    _load();
  }

  Future<void> _deletePlan() async {
    final confirmed = await AppFeedback.confirmDelete(
      context,
      title: Text('Delete "${_plan?.name}"?',
          style: GoogleFonts.playfairDisplay(fontSize: 18)),
      content: const Text('This permanently deletes the plan and all tasks.'),
      accentColor: const Color(0xFFC64545),
    );
    if (!confirmed || !mounted) return;
    final nav = Navigator.of(context);
    await _taskRepo.deleteByPlan(widget.planId);
    await _dayRepo.deleteByPlan(widget.planId);
    await _planRepo.delete(widget.planId);
    nav.pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading || _plan == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final plan = _plan!;
    final today = _days.firstWhere((d) => d.isToday, orElse: () => _days.first);
    final todayTasks = _tasksByDay[today.id] ?? [];
    final isTodayReal = today.isToday;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(plan.name,
            style: GoogleFonts.playfairDisplay(
                fontSize: 18, letterSpacing: -0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editPlan();
              if (v == 'toggle') _toggleStatus();
              if (v == 'delete') _deletePlan();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  const Icon(Icons.edit_outlined, size: 16),
                  const SizedBox(width: 8),
                  Text('Edit Plan', style: GoogleFonts.inter(fontSize: 14)),
                ]),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Row(children: [
                  Icon(
                    plan.isActive
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(plan.isActive ? 'Pause' : 'Resume',
                      style: GoogleFonts.inter(fontSize: 14)),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  const Icon(Icons.delete_outline_rounded,
                      size: 16, color: Color(0xFFC64545)),
                  const SizedBox(width: 8),
                  Text('Delete',
                      style: GoogleFonts.inter(
                          fontSize: 14, color: const Color(0xFFC64545))),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Progress card ────────────────────────────────────────────────
          _ProgressCard(
            plan: plan,
            totalTasks: _totalTasks,
            completedTasks: _completedTasks,
            completedDays: _completedDays,
            totalDays: _days.length,
            progress: _progress,
            isDark: isDark,
          ),
          const SizedBox(height: 16),

          // ── Today's pipeline ─────────────────────────────────────────────
          if (isTodayReal && todayTasks.isNotEmpty) ...[
            _TodaySection(
              day: today,
              tasks: todayTasks,
              isDark: isDark,
              onToggle: (task) => _toggleTask(today, task),
            ),
            const SizedBox(height: 20),
            _SectionLabel('Full Schedule', isDark: isDark),
            const SizedBox(height: 8),
          ],

          // ── All days timeline ────────────────────────────────────────────
          ..._days.map((day) {
            final tasks = _tasksByDay[day.id] ?? [];
            return _DayTile(
              day: day,
              tasks: tasks,
              isDark: isDark,
              expanded: _expanded.contains(day.id),
              onToggleExpand: () => setState(() {
                if (_expanded.contains(day.id)) {
                  _expanded.remove(day.id);
                } else {
                  _expanded.add(day.id);
                }
              }),
              onToggleTask: (task) => _toggleTask(day, task),
            );
          }),
        ],
      ),
    );
  }
}

// ── Progress Card ─────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  final StudyPlan plan;
  final int totalTasks;
  final int completedTasks;
  final int completedDays;
  final int totalDays;
  final double progress;
  final bool isDark;

  const _ProgressCard({
    required this.plan,
    required this.totalTasks,
    required this.completedTasks,
    required this.completedDays,
    required this.totalDays,
    required this.progress,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final textColor =
        isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    final isComplete = plan.isCompleted || progress >= 1.0;
    final progressColor = isComplete ? const Color(0xFF5DB872) : _coral;

    final daysToExam = plan.daysToExam;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        Row(children: [
          // Ring
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 72,
                height: 72,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 7,
                  backgroundColor: isDark
                      ? const Color(0xFF2E2C28)
                      : const Color(0xFFE6DFD8),
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 16, color: textColor, letterSpacing: -0.3),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(plan.name,
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 15,
                      color: textColor,
                      letterSpacing: -0.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              if (daysToExam >= 0)
                Text(
                  daysToExam == 0
                      ? 'Exam is today!'
                      : '$daysToExam day${daysToExam != 1 ? 's' : ''} to exam',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: daysToExam <= 3 ? const Color(0xFFC64545) : muted),
                ),
              const SizedBox(height: 2),
              Text(
                'Exam: ${DateFormat('EEE d MMM').format(plan.examDate)}',
                style: GoogleFonts.inter(fontSize: 11, color: muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        // Stats row
        Row(children: [
          _StatPill(
            value: '$completedTasks/$totalTasks',
            label: 'Tasks',
            color: progressColor,
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _StatPill(
            value: '$completedDays/$totalDays',
            label: 'Days',
            color: const Color(0xFF5B86C8),
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _StatPill(
            value: daysToExam >= 0 ? '$daysToExam' : '—',
            label: 'Until exam',
            color: daysToExam >= 0 && daysToExam <= 3
                ? const Color(0xFFC64545)
                : const Color(0xFFE8A55A),
            isDark: isDark,
          ),
        ]),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _StatPill(
      {required this.value,
      required this.label,
      required this.color,
      required this.isDark});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Text(value,
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    color: color.withValues(alpha: 0.7))),
          ]),
        ),
      );
}

// ── Today Section (Pipeline) ──────────────────────────────────────────────────

class _TodaySection extends StatelessWidget {
  final StudyDay day;
  final List<StudyTask> tasks;
  final bool isDark;
  final void Function(StudyTask) onToggle;

  const _TodaySection({
    required this.day,
    required this.tasks,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final completed = tasks.where((t) => t.isCompleted).length;
    final total = tasks.length;
    final allDone = completed == total;

    // Find "current" task — the next incomplete one
    final currentIdx = tasks.indexWhere((t) => !t.isCompleted);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('✦ Today',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _coral,
                letterSpacing: 0.5)),
        const SizedBox(width: 8),
        Text(DateFormat('EEE, d MMM').format(day.date),
            style: GoogleFonts.inter(fontSize: 11, color: muted)),
        const Spacer(),
        Text('$completed/$total',
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: allDone ? const Color(0xFF5DB872) : muted)),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: allDone
                  ? const Color(0xFF5DB872).withValues(alpha: 0.3)
                  : _coral.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: tasks.asMap().entries.map((e) {
            final i = e.key;
            final task = e.value;
            final isCurrent = i == currentIdx;
            final isLast = i == tasks.length - 1;

            return _PipelineTask(
              task: task,
              isCurrent: isCurrent,
              isLast: isLast,
              isDark: isDark,
              onToggle: () => onToggle(task),
            );
          }).toList(),
        ),
      ),
      if (allDone) ...[
        const SizedBox(height: 10),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF5DB872).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.celebration_rounded,
                size: 16, color: Color(0xFF5DB872)),
            const SizedBox(width: 8),
            Text('All tasks done for today! Great work.',
                style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF5DB872),
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ],
    ]);
  }
}

class _PipelineTask extends StatelessWidget {
  final StudyTask task;
  final bool isCurrent;
  final bool isLast;
  final bool isDark;
  final VoidCallback onToggle;

  const _PipelineTask({
    required this.task,
    required this.isCurrent,
    required this.isLast,
    required this.isDark,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final textColor =
        isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: border)),
        color: isCurrent ? _coral.withValues(alpha: 0.04) : null,
      ),
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(children: [
            // Step indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: task.isCompleted
                    ? const Color(0xFF5DB872)
                    : isCurrent
                        ? _coral
                        : Colors.transparent,
                border: task.isCompleted || isCurrent
                    ? null
                    : Border.all(
                        color: isDark
                            ? const Color(0xFF3E3C38)
                            : const Color(0xFFD4CEC8),
                        width: 2),
              ),
              child: Icon(
                task.isCompleted
                    ? Icons.check_rounded
                    : isCurrent
                        ? Icons.play_arrow_rounded
                        : null,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  task.title,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: task.isCompleted
                        ? muted
                        : textColor,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: muted,
                  ),
                ),
                if (task.chapterName != null) ...[
                  const SizedBox(height: 2),
                  Text(task.chapterName!,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: muted)),
                ],
                if (task.description != null &&
                    task.description!.isNotEmpty &&
                    isCurrent) ...[
                  const SizedBox(height: 4),
                  Text(task.description!,
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: muted,
                          height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: (isCurrent ? _coral : muted)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _fmtMin(task.durationMinutes),
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isCurrent ? _coral : muted),
                ),
              ),
            ]),
          ]),
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

// ── Day Tile ──────────────────────────────────────────────────────────────────

class _DayTile extends StatelessWidget {
  final StudyDay day;
  final List<StudyTask> tasks;
  final bool isDark;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final void Function(StudyTask) onToggleTask;

  const _DayTile({
    required this.day,
    required this.tasks,
    required this.isDark,
    required this.expanded,
    required this.onToggleExpand,
    required this.onToggleTask,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFFFEFC);
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final textColor =
        isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    final completed = tasks.where((t) => t.isCompleted).length;
    final total = tasks.length;
    final allDone = total > 0 && completed == total;
    final isPast = day.isPast && !day.isToday;
    final isToday = day.isToday;

    Color accentColor;
    if (allDone) {
      accentColor = const Color(0xFF5DB872);
    } else if (isToday) {
      accentColor = _coral;
    } else if (isPast) {
      accentColor = muted;
    } else {
      accentColor = const Color(0xFF5B86C8);
    }

    final totalMin =
        tasks.fold(0, (s, t) => s + t.durationMinutes);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isToday
                ? _coral.withValues(alpha: 0.3)
                : border),
      ),
      child: Column(children: [
        // Header
        InkWell(
          onTap: tasks.isEmpty ? null : onToggleExpand,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Row(children: [
              // Status dot / check
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: allDone
                      ? const Color(0xFF5DB872).withValues(alpha: 0.12)
                      : accentColor.withValues(alpha: 0.08),
                ),
                child: Icon(
                  allDone
                      ? Icons.check_rounded
                      : isToday
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Text(
                          DateFormat('EEE, d MMM').format(day.date),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isPast && !allDone ? muted : textColor,
                          ),
                        ),
                        if (isToday) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _coral,
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text('Today',
                                style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.3)),
                          ),
                        ],
                      ]),
                      Text(
                        tasks.isEmpty
                            ? 'No tasks'
                            : '$completed/$total · ${_fmtMin(totalMin)}',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: muted),
                      ),
                    ]),
                  ),
                ]),
              ),
              if (tasks.isNotEmpty)
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    color: muted, size: 18),
            ]),
          ),
        ),
        // Tasks
        if (expanded && tasks.isNotEmpty) ...[
          Divider(height: 1, color: border),
          ...tasks.map((task) => _TaskCheckTile(
                task: task,
                isDark: isDark,
                onToggle: () => onToggleTask(task),
              )),
        ],
      ]),
    );
  }

  String _fmtMin(int min) {
    if (min < 60) return '${min}m';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

class _TaskCheckTile extends StatelessWidget {
  final StudyTask task;
  final bool isDark;
  final VoidCallback onToggle;

  const _TaskCheckTile(
      {required this.task, required this.isDark, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final textColor =
        isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: border))),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: task.isCompleted
                  ? const Color(0xFF5DB872)
                  : Colors.transparent,
              border: task.isCompleted
                  ? null
                  : Border.all(color: muted, width: 1.5),
            ),
            child: task.isCompleted
                ? const Icon(Icons.check_rounded,
                    size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                task.title,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: task.isCompleted ? muted : textColor,
                  decoration: task.isCompleted
                      ? TextDecoration.lineThrough
                      : null,
                  decorationColor: muted,
                ),
              ),
              if (task.chapterName != null)
                Text(task.chapterName!,
                    style: GoogleFonts.inter(fontSize: 11, color: muted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: muted.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _fmtMin(task.durationMinutes),
              style:
                  GoogleFonts.inter(fontSize: 10, color: muted),
            ),
          ),
        ]),
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

// ── Section Label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionLabel(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color:
              isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64),
        ),
      );
}
