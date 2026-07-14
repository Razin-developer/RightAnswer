import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/chapter.dart';
import '../models/study_day.dart';
import '../models/study_plan.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/study_day_repository.dart';
import '../repositories/study_plan_repository.dart';
import '../repositories/study_task_repository.dart';
import '../repositories/subject_repository.dart';
import '../services/notification_service.dart';
import '../services/study_plan_ai_service.dart';
import '../widgets/app_feedback.dart';

const _coral = Color(0xFFCC785C);

enum _Phase { config, generating, review }

class StudyPlanCreateScreen extends StatefulWidget {
  final StudyPlan? existingPlan;

  const StudyPlanCreateScreen({super.key, this.existingPlan});

  @override
  State<StudyPlanCreateScreen> createState() => _StudyPlanCreateScreenState();
}

class _StudyPlanCreateScreenState extends State<StudyPlanCreateScreen> {
  final _planRepo = StudyPlanRepository();
  final _dayRepo = StudyDayRepository();
  final _taskRepo = StudyTaskRepository();
  final _aiService = StudyPlanAIService.instance;

  // ── Phase ──────────────────────────────────────────────────────────────────
  _Phase _phase = _Phase.config;

  // ── Config fields ──────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  DateTime _examDate = DateTime.now().add(const Duration(days: 30));
  DateTime _startDate = DateTime.now();
  List<int> _freeDays = [6, 7]; // Sat, Sun free by default
  double _hoursPerDay = 2.0;
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 0);

  // Subject & chapter selection
  String? _subjectId;
  String? _subjectName;
  final List<String> _chapterIds = [];
  final List<String> _chapterNames = [];

  // ── Generated plan (draft) ─────────────────────────────────────────────────
  StudyPlanDraft? _draft;

  // ── Saving ─────────────────────────────────────────────────────────────────
  bool _saving = false;

  bool get _isEdit => widget.existingPlan != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.existingPlan!;
      _nameCtrl.text = p.name;
      _examDate = p.examDate;
      _startDate = p.startDate;
      _freeDays = List.from(p.freeDays);
      _hoursPerDay = p.hoursPerDay;
      _subjectId = p.subjectId;
      _subjectName = p.subjectName;
      _chapterIds.addAll(p.chapterIds);
      _chapterNames.addAll(p.chapterNames);
      if (p.hasReminder) {
        _reminderEnabled = true;
        _reminderTime =
            TimeOfDay(hour: p.reminderHour!, minute: p.reminderMinute!);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── AI generation ──────────────────────────────────────────────────────────

  Future<void> _generate() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppFeedback.showToast(context, 'Enter a plan name first');
      return;
    }
    if (_examDate.isBefore(_startDate)) {
      AppFeedback.showToast(context, 'Exam date must be after start date');
      return;
    }

    setState(() => _phase = _Phase.generating);
    try {
      final draft = await _aiService.generatePlan(
        planName: name,
        examDate: _examDate,
        startDate: _startDate,
        freeDays: _freeDays,
        hoursPerDay: _hoursPerDay,
        chapterIds: _chapterIds,
        chapterNames: _chapterNames,
        subjectName: _subjectName,
      );
      if (draft.suggestedName.isNotEmpty &&
          _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = draft.suggestedName;
      }
      if (mounted) {
        setState(() {
          _draft = draft;
          _phase = _Phase.review;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _phase = _Phase.config);
        AppFeedback.showErrorToast(context, e.toString());
      }
    }
  }

  Future<void> _refineWithAI() async {
    final ctrl = TextEditingController();
    final instruction = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Refine with AI',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText:
                'e.g. "Add more review sessions" or "Focus more on chapter 3"',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _coral),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Refine'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (instruction == null || instruction.isEmpty || _draft == null) return;

    setState(() => _phase = _Phase.generating);
    try {
      final refined = await _aiService.refinePlan(
        current: _draft!,
        instruction: instruction,
        subjectName: _subjectName,
      );
      if (mounted) {
        setState(() {
          _draft = refined;
          _phase = _Phase.review;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _phase = _Phase.review);
        AppFeedback.showErrorToast(context, e.toString());
      }
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_draft == null || _draft!.days.isEmpty) {
      AppFeedback.showToast(context, 'Nothing to save — generate a plan first');
      return;
    }
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppFeedback.showToast(context, 'Enter a plan name');
      return;
    }
    setState(() => _saving = true);

    try {
      final now = DateTime.now();
      final planId = _isEdit ? widget.existingPlan!.id : const Uuid().v4();

      final plan = StudyPlan(
        id: planId,
        name: name.isEmpty ? (_draft!.suggestedName) : name,
        subjectId: _subjectId,
        subjectName: _subjectName,
        chapterIds: List.from(_chapterIds),
        chapterNames: List.from(_chapterNames),
        examDate: _examDate,
        startDate: _startDate,
        freeDays: List.from(_freeDays),
        hoursPerDay: _hoursPerDay,
        status: 'active',
        reminderHour: _reminderEnabled ? _reminderTime.hour : null,
        reminderMinute: _reminderEnabled ? _reminderTime.minute : null,
        createdAt: _isEdit ? widget.existingPlan!.createdAt : now,
        updatedAt: now,
      );

      if (_isEdit) {
        await _planRepo.update(plan);
        await _taskRepo.deleteByPlan(planId);
        await _dayRepo.deleteByPlan(planId);
      } else {
        await _planRepo.insert(plan);
      }

      for (final dayDraft in _draft!.days) {
        final dayId = const Uuid().v4();
        final day = StudyDay(
          id: dayId,
          planId: planId,
          date: dayDraft.date,
        );
        await _dayRepo.insert(day);

        for (var i = 0; i < dayDraft.tasks.length; i++) {
          final t = dayDraft.tasks[i];
          await _taskRepo.insert(StudyTask(
            id: const Uuid().v4(),
            planId: planId,
            dayId: dayId,
            title: t.title,
            description: t.description.isEmpty ? null : t.description,
            chapterId: t.chapterId,
            chapterName: t.chapterName,
            durationMinutes: t.durationMinutes,
            sortOrder: i,
          ));
        }
      }

      // Schedule / cancel reminder
      if (_reminderEnabled) {
        await NotificationService.instance.requestPermission();
        await NotificationService.instance.scheduleStudyPlanReminder(
          planId: planId,
          planName: plan.name,
          hour: _reminderTime.hour,
          minute: _reminderTime.minute,
        );
      } else if (_isEdit && widget.existingPlan!.hasReminder) {
        await NotificationService.instance.cancelStudyPlanReminder(planId);
      }

      if (mounted) {
        AppFeedback.showSuccessToast(
            context, _isEdit ? 'Plan updated' : 'Plan created!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showErrorToast(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Edit Plan' : 'New Study Plan',
          style:
              GoogleFonts.playfairDisplay(fontSize: 19, letterSpacing: -0.3),
        ),
        centerTitle: false,
        actions: [
          if (_phase == _Phase.review && !_saving)
            TextButton(
              onPressed: _save,
              child: Text('Save',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700, color: _coral)),
            ),
          if (_saving)
            const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      ),
      body: switch (_phase) {
        _Phase.generating => _buildGenerating(isDark),
        _Phase.review => _buildReview(isDark),
        _ => _buildConfig(isDark),
      },
    );
  }

  // ── Config phase ───────────────────────────────────────────────────────────

  Widget _buildConfig(bool isDark) {
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        _ConfigSection(
          label: 'Plan Details',
          isDark: isDark,
          child: Column(children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: 'Plan name',
                hintText: 'e.g. "Physics Final Exam Prep"',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                prefixIcon: const Icon(Icons.bookmark_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _DateTile(
              label: 'Exam date',
              date: _examDate,
              icon: Icons.event_rounded,
              isDark: isDark,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _examDate,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (d != null) setState(() => _examDate = d);
              },
            ),
            const SizedBox(height: 8),
            _DateTile(
              label: 'Start studying',
              date: _startDate,
              icon: Icons.play_circle_outline_rounded,
              isDark: isDark,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: _examDate,
                );
                if (d != null) setState(() => _startDate = d);
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        _ConfigSection(
          label: 'Content',
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => _openChapterSheet(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(Icons.menu_book_outlined, size: 18, color: _coral),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _chapterNames.isEmpty
                            ? 'Select chapters / topics'
                            : _chapterNames.join(', '),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: _chapterNames.isEmpty ? muted : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: muted, size: 18),
                  ]),
                ),
              ),
              if (_chapterNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _chapterNames
                      .asMap()
                      .entries
                      .map((e) => _ChapterChip(
                            label: e.value,
                            onRemove: () => setState(() {
                              _chapterNames.removeAt(e.key);
                              if (e.key < _chapterIds.length) {
                                _chapterIds.removeAt(e.key);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ConfigSection(
          label: 'Schedule',
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Days off (won\'t schedule tasks)',
                  style: GoogleFonts.inter(fontSize: 12, color: muted)),
              const SizedBox(height: 8),
              _FreeDayPicker(
                freeDays: _freeDays,
                isDark: isDark,
                onChanged: (days) => setState(() => _freeDays = days),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Study time per day',
                      style: GoogleFonts.inter(fontSize: 13)),
                  Text(
                    _hoursLabel(_hoursPerDay),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _coral),
                  ),
                ],
              ),
              Slider(
                value: _hoursPerDay,
                min: 0.5,
                max: 8.0,
                divisions: 15,
                activeColor: _coral,
                onChanged: (v) => setState(() => _hoursPerDay = v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('30m', style: GoogleFonts.inter(fontSize: 11, color: muted)),
                  Text('8h', style: GoogleFonts.inter(fontSize: 11, color: muted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ConfigSection(
          label: 'Daily Reminder',
          isDark: isDark,
          child: Column(children: [
            Row(children: [
              Switch(
                value: _reminderEnabled,
                activeThumbColor: _coral,
                onChanged: (v) async {
                  if (v) {
                    final granted =
                        await NotificationService.instance.requestPermission();
                    if (!granted && mounted) {
                      AppFeedback.showToast(
                          context, 'Enable notifications in settings');
                      return;
                    }
                  }
                  setState(() => _reminderEnabled = v);
                },
              ),
              const SizedBox(width: 10),
              Text(
                _reminderEnabled
                    ? 'Remind me daily at ${_reminderTime.format(context)}'
                    : 'No daily reminder',
                style: GoogleFonts.inter(fontSize: 13),
              ),
            ]),
            if (_reminderEnabled) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time_rounded, size: 16),
                label: Text('Change time: ${_reminderTime.format(context)}',
                    style: GoogleFonts.inter(fontSize: 13)),
                onPressed: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: _reminderTime);
                  if (t != null) setState(() => _reminderTime = t);
                },
              ),
            ],
          ]),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome_rounded, size: 18),
          label: Text('Generate Plan with AI',
              style:
                  GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
          style: FilledButton.styleFrom(
            backgroundColor: _coral,
            minimumSize: const Size(double.infinity, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _generate,
        ),
      ],
    );
  }

  // ── Generating phase ───────────────────────────────────────────────────────

  Widget _buildGenerating(bool isDark) {
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: _coral),
            ),
            const SizedBox(height: 24),
            Text(
              'Building your plan…',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 20, letterSpacing: -0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'The AI is scheduling your chapters\nacross your available study days.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 13, color: muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Review phase ───────────────────────────────────────────────────────────

  Widget _buildReview(bool isDark) {
    final draft = _draft!;
    final totalTasks = draft.days.fold(0, (s, d) => s + d.tasks.length);
    final totalMin =
        draft.days.fold(0, (s, d) => s + d.tasks.fold(0, (ss, t) => ss + t.durationMinutes));

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFFFEFC),
          child: Row(children: [
            _SummaryChip(
                label: '${draft.days.length} days',
                icon: Icons.calendar_today_outlined,
                isDark: isDark),
            const SizedBox(width: 8),
            _SummaryChip(
                label: '$totalTasks tasks',
                icon: Icons.task_outlined,
                isDark: isDark),
            const SizedBox(width: 8),
            _SummaryChip(
                label: _fmtMin(totalMin),
                icon: Icons.timer_outlined,
                isDark: isDark),
            const Spacer(),
            TextButton.icon(
              onPressed: _refineWithAI,
              icon: const Icon(Icons.auto_awesome_rounded, size: 14),
              label: Text('Refine',
                  style: GoogleFonts.inter(fontSize: 12, color: _coral)),
              style: TextButton.styleFrom(foregroundColor: _coral),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: draft.days.length,
            itemBuilder: (_, i) => _DayDraftCard(
              index: i,
              dayDraft: draft.days[i],
              isDark: isDark,
              onTaskEdit: (taskIdx, updated) => setState(() {
                draft.days[i].tasks[taskIdx] = updated;
              }),
              onTaskDelete: (taskIdx) => setState(() {
                draft.days[i].tasks.removeAt(taskIdx);
              }),
              onTaskAdd: () => setState(() {
                draft.days[i].tasks.add(StudyTaskDraft(
                  title: 'New task',
                  description: '',
                  durationMinutes: 60,
                ));
              }),
            ),
          ),
        ),
      ],
    );
  }

  // ── Chapter sheet ──────────────────────────────────────────────────────────

  Future<void> _openChapterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ChapterSheet(
        selectedIds: List.from(_chapterIds),
        selectedNames: List.from(_chapterNames),
        subjectId: _subjectId,
        onDone: (ids, names, sId, sName) {
          setState(() {
            _chapterIds
              ..clear()
              ..addAll(ids);
            _chapterNames
              ..clear()
              ..addAll(names);
            _subjectId = sId;
            _subjectName = sName;
          });
        },
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _hoursLabel(double h) {
    final i = h.toInt();
    final m = ((h - i) * 60).toInt();
    return m == 0 ? '${i}h' : '${i}h ${m}m';
  }

  String _fmtMin(int min) {
    if (min < 60) return '${min}m';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ── Config Section ─────────────────────────────────────────────────────────────

class _ConfigSection extends StatelessWidget {
  final String label;
  final Widget child;
  final bool isDark;

  const _ConfigSection(
      {required this.label, required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFFFEFC);
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: muted,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ── Date Tile ─────────────────────────────────────────────────────────────────

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.date,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: _coral),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: GoogleFonts.inter(fontSize: 11, color: muted)),
            Text(
              DateFormat('EEE, d MMM yyyy').format(date),
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ]),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: muted, size: 18),
        ]),
      ),
    );
  }
}

// ── Free Day Picker ───────────────────────────────────────────────────────────

class _FreeDayPicker extends StatelessWidget {
  final List<int> freeDays;
  final bool isDark;
  final ValueChanged<List<int>> onChanged;

  const _FreeDayPicker(
      {required this.freeDays, required this.isDark, required this.onChanged});

  static const _days = [
    (1, 'M'),
    (2, 'T'),
    (3, 'W'),
    (4, 'T'),
    (5, 'F'),
    (6, 'S'),
    (7, 'S'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _days.map((d) {
        final (num, label) = d;
        final isFree = freeDays.contains(num);
        return GestureDetector(
          onTap: () {
            final updated = List<int>.from(freeDays);
            if (isFree) {
              updated.remove(num);
            } else {
              updated.add(num);
            }
            onChanged(updated);
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isFree
                  ? (isDark
                      ? const Color(0xFF2E2C28)
                      : const Color(0xFFE6DFD8))
                  : _coral.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: isFree
                      ? Colors.transparent
                      : _coral.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isFree
                    ? (isDark
                        ? const Color(0xFF8E8B82)
                        : const Color(0xFF6C6A64))
                    : _coral,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Chapter Chip ──────────────────────────────────────────────────────────────

class _ChapterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ChapterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) => Chip(
        label: Text(label, style: GoogleFonts.inter(fontSize: 11)),
        deleteIcon: const Icon(Icons.close, size: 14),
        onDeleted: onRemove,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );
}

// ── Summary Chip ──────────────────────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;

  const _SummaryChip(
      {required this.label, required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: muted),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.inter(fontSize: 12, color: muted)),
    ]);
  }
}

// ── Day Draft Card ────────────────────────────────────────────────────────────

class _DayDraftCard extends StatefulWidget {
  final int index;
  final StudyDayDraft dayDraft;
  final bool isDark;
  final void Function(int taskIdx, StudyTaskDraft updated) onTaskEdit;
  final void Function(int taskIdx) onTaskDelete;
  final VoidCallback onTaskAdd;

  const _DayDraftCard({
    required this.index,
    required this.dayDraft,
    required this.isDark,
    required this.onTaskEdit,
    required this.onTaskDelete,
    required this.onTaskAdd,
  });

  @override
  State<_DayDraftCard> createState() => _DayDraftCardState();
}

class _DayDraftCardState extends State<_DayDraftCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand today's day and the first day
    final now = DateTime.now();
    final today =
        DateTime(now.year, now.month, now.day);
    final d = DateTime(widget.dayDraft.date.year, widget.dayDraft.date.month,
        widget.dayDraft.date.day);
    _expanded = widget.index == 0 || d == today;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFFFEFC);
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final textColor =
        isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    final day = widget.dayDraft;
    final totalMin =
        day.tasks.fold(0, (s, t) => s + t.durationMinutes);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(children: [
        // Header
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _coral.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${widget.index + 1}',
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _coral),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    DateFormat('EEE, d MMM').format(day.date),
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor),
                  ),
                  Text(
                    '${day.tasks.length} tasks · ${_fmtMin(totalMin)}',
                    style: GoogleFonts.inter(fontSize: 11, color: muted),
                  ),
                ]),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: muted,
                size: 20,
              ),
            ]),
          ),
        ),
        // Tasks
        if (_expanded) ...[
          Divider(height: 1, color: border),
          ...day.tasks.asMap().entries.map((e) => _TaskDraftTile(
                task: e.value,
                isDark: isDark,
                onEdit: () async {
                  final updated =
                      await _showEditDialog(context, e.value, isDark);
                  if (updated != null) widget.onTaskEdit(e.key, updated);
                },
                onDelete: () => widget.onTaskDelete(e.key),
              )),
          // Add task button
          InkWell(
            onTap: widget.onTaskAdd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(Icons.add_rounded, size: 16, color: _coral),
                const SizedBox(width: 8),
                Text('Add task',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: _coral,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Future<StudyTaskDraft?> _showEditDialog(
      BuildContext context, StudyTaskDraft task, bool isDark) async {
    final titleCtrl = TextEditingController(text: task.title);
    final descCtrl = TextEditingController(text: task.description);
    int duration = task.durationMinutes;

    final result = await showDialog<StudyTaskDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Edit Task',
              style: GoogleFonts.playfairDisplay(fontSize: 17)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: duration,
                decoration: const InputDecoration(
                  labelText: 'Duration',
                  border: OutlineInputBorder(),
                ),
                items: [30, 60, 90, 120, 150, 180]
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(_fmtMin(m))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setSt(() => duration = v);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _coral),
              onPressed: () => Navigator.pop(
                ctx,
                StudyTaskDraft(
                  title: titleCtrl.text.trim().isEmpty
                      ? task.title
                      : titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  chapterId: task.chapterId,
                  chapterName: task.chapterName,
                  durationMinutes: duration,
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    titleCtrl.dispose();
    descCtrl.dispose();
    return result;
  }

  String _fmtMin(int min) {
    if (min < 60) return '${min}m';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}

// ── Task Draft Tile ───────────────────────────────────────────────────────────

class _TaskDraftTile extends StatelessWidget {
  final StudyTaskDraft task;
  final bool isDark;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskDraftTile({
    required this.task,
    required this.isDark,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final textColor =
        isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    return Dismissible(
      key: ValueKey(task.title + task.durationMinutes.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: const Color(0xFFC64545).withValues(alpha: 0.1),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFC64545)),
      ),
      onDismissed: (_) => onDelete(),
      child: InkWell(
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: border))),
          child: Row(children: [
            Container(
              width: 4,
              height: 32,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: _coral.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(task.title,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (task.chapterName != null && task.chapterName!.isNotEmpty)
                  Text(task.chapterName!,
                      style:
                          GoogleFonts.inter(fontSize: 11, color: muted)),
              ]),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: _coral.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _fmtMin(task.durationMinutes),
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _coral),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, size: 14, color: muted),
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

// ── Chapter Sheet ─────────────────────────────────────────────────────────────

class _ChapterSheet extends StatefulWidget {
  final List<String> selectedIds;
  final List<String> selectedNames;
  final String? subjectId;
  final void Function(
      List<String> ids, List<String> names, String? sId, String? sName) onDone;

  const _ChapterSheet({
    required this.selectedIds,
    required this.selectedNames,
    required this.subjectId,
    required this.onDone,
  });

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();

  List<Subject> _subjects = [];
  List<Chapter> _chapters = [];
  Subject? _selectedSubject;
  final Set<String> _selIds = {};
  final Map<String, String> _selNames = {};

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.selectedIds.length; i++) {
      _selIds.add(widget.selectedIds[i]);
      if (i < widget.selectedNames.length) {
        _selNames[widget.selectedIds[i]] = widget.selectedNames[i];
      }
    }
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final subs = await _subjectRepo.getAll();
    Subject? sel;
    if (widget.subjectId != null) {
      try {
        sel = subs.firstWhere((s) => s.id == widget.subjectId);
      } catch (_) {}
    }
    sel ??= subs.isNotEmpty ? subs.first : null;
    setState(() => _subjects = subs);
    if (sel != null) _selectSubject(sel);
  }

  Future<void> _selectSubject(Subject s) async {
    setState(() {
      _selectedSubject = s;
      _chapters = [];
    });
    final chapters = await _chapterRepo.getBySubject(s.id);
    if (mounted) setState(() => _chapters = chapters);
  }

  void _done() {
    final ids = _selIds.toList();
    final names = ids.map((id) => _selNames[id] ?? id).toList();
    widget.onDone(ids, names, _selectedSubject?.id, _selectedSubject?.name);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF181715) : const Color(0xFFFAF9F5);
    final cardBg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final border =
        isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final muted = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scroll) => Container(
        color: bg,
        child: Column(children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(children: [
              Text('Select Chapters',
                  style: GoogleFonts.playfairDisplay(fontSize: 18)),
              const Spacer(),
              Text('${_selIds.length} selected',
                  style: GoogleFonts.inter(fontSize: 12, color: muted)),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: _coral,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 16)),
                onPressed: _done,
                child: Text('Done',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ]),
          ),
          Expanded(
            child: Row(children: [
              // Subject list
              SizedBox(
                width: 130,
                child: Container(
                  decoration:
                      BoxDecoration(border: Border(right: BorderSide(color: border))),
                  child: ListView.builder(
                    itemCount: _subjects.length,
                    itemBuilder: (_, i) {
                      final s = _subjects[i];
                      final selected = s.id == _selectedSubject?.id;
                      return InkWell(
                        onTap: () => _selectSubject(s),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                          color: selected
                              ? _coral.withValues(alpha: 0.08)
                              : null,
                          child: Text(
                            s.name,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: selected ? _coral : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Chapter list
              Expanded(
                child: _chapters.isEmpty
                    ? Center(
                        child: Text('No chapters',
                            style:
                                GoogleFonts.inter(fontSize: 13, color: muted)))
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.all(8),
                        itemCount: _chapters.length,
                        itemBuilder: (_, i) {
                          final c = _chapters[i];
                          final sel = _selIds.contains(c.id);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: sel
                                  ? _coral.withValues(alpha: 0.08)
                                  : cardBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: sel
                                      ? _coral.withValues(alpha: 0.3)
                                      : border),
                            ),
                            child: CheckboxListTile(
                              value: sel,
                              activeColor: _coral,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              title: Text(c.title,
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: sel
                                          ? FontWeight.w600
                                          : FontWeight.w400)),
                              subtitle: c.className.isNotEmpty
                                  ? Text(c.className,
                                      style: GoogleFonts.inter(
                                          fontSize: 11, color: muted))
                                  : null,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selIds.add(c.id);
                                    _selNames[c.id] = c.title;
                                  } else {
                                    _selIds.remove(c.id);
                                    _selNames.remove(c.id);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
