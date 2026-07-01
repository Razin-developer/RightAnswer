import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/exam.dart';
import '../repositories/exam_attempt_repository.dart';
import '../repositories/exam_message_repository.dart';
import '../repositories/exam_question_repository.dart';
import '../repositories/exam_repository.dart';
import '../widgets/app_feedback.dart';
import 'exam_attempt_screen.dart';
import 'exam_create_screen.dart';

// ── Type helpers ──────────────────────────────────────────────────────────────

class ExamTypeInfo {
  static String label(String t) => switch (t) {
    'mcq' => 'MCQ',
    'true_false' => 'True / False',
    'fill_blank' => 'Fill in Blank',
    'short_answer' => 'Short Answer',
    'long_answer' => 'Long Answer',
    'mixed' => 'Mixed',
    _ => t,
  };

  static IconData icon(String t) => switch (t) {
    'mcq' => Icons.radio_button_checked_rounded,
    'true_false' => Icons.toggle_on_rounded,
    'fill_blank' => Icons.text_fields_rounded,
    'short_answer' => Icons.short_text_rounded,
    'long_answer' => Icons.article_outlined,
    'mixed' => Icons.auto_awesome_rounded,
    _ => Icons.quiz_outlined,
  };

  static Color color(String t) => switch (t) {
    'mcq' => const Color(0xFFCC785C),
    'true_false' => const Color(0xFF5DB8A6),
    'fill_blank' => const Color(0xFFE8A55A),
    'short_answer' => const Color(0xFF9B72CF),
    'long_answer' => const Color(0xFF5B86C8),
    'mixed' => const Color(0xFFD4607A),
    _ => const Color(0xFFCC785C),
  };
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class ExamScreen extends StatefulWidget {
  const ExamScreen({super.key});

  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  final _examRepo = ExamRepository();
  final _questionRepo = ExamQuestionRepository();
  final _messageRepo = ExamMessageRepository();
  final _attemptRepo = ExamAttemptRepository();

  List<Exam> _exams = [];
  Map<String, int> _attemptCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final exams = await _examRepo.getAll();
    final counts = <String, int>{};
    for (final e in exams) {
      counts[e.id] = await _attemptRepo.countByExam(e.id);
    }
    if (mounted) setState(() { _exams = exams; _attemptCounts = counts; _loading = false; });
  }

  Future<void> _deleteExam(Exam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${exam.name}"?',
            style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: const Text('This will permanently delete the exam and all its attempts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC64545)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _attemptRepo.deleteByExam(exam.id);
    await _messageRepo.deleteByExam(exam.id);
    await _questionRepo.deleteByExam(exam.id);
    await _examRepo.delete(exam.id);
    _load();
  }

  Future<void> _startExam(Exam exam) async {
    final attemptCount = _attemptCounts[exam.id] ?? 0;
    if (exam.maxAttempts > 0 && attemptCount >= exam.maxAttempts) {
      if (!mounted) return;
      AppFeedback.showToast(context, 'Attempt limit reached (${exam.maxAttempts})');
      return;
    }
    final questions = await _questionRepo.getByExam(exam.id);
    if (questions.isEmpty) {
      if (!mounted) return;
      AppFeedback.showToast(context, 'No questions yet — edit this exam first');
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamAttemptScreen(exam: exam, questions: questions),
      ),
    );
    _load();
  }

  Future<void> _openCreate() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExamCreateScreen()),
    );
    _load();
  }

  Future<void> _openEdit(Exam exam) async {
    final questions = await _questionRepo.getByExam(exam.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamCreateScreen(exam: exam, existingQuestions: questions),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Exams', style: GoogleFonts.playfairDisplay(fontSize: 20, letterSpacing: -0.3)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _exams.isEmpty
          ? _EmptyState(onAdd: _openCreate)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: _exams.length,
                itemBuilder: (ctx, i) => _ExamCard(
                  exam: _exams[i],
                  attemptCount: _attemptCounts[_exams[i].id] ?? 0,
                  isDark: isDark,
                  onStart: () => _startExam(_exams[i]),
                  onEdit: () => _openEdit(_exams[i]),
                  onDelete: () => _deleteExam(_exams[i]),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: const Color(0xFFCC785C),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add Exam', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        elevation: 2,
      ),
    );
  }
}

// ── Exam Card ─────────────────────────────────────────────────────────────────

class _ExamCard extends StatelessWidget {
  final Exam exam;
  final int attemptCount;
  final bool isDark;
  final VoidCallback onStart;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExamCard({
    required this.exam,
    required this.attemptCount,
    required this.isDark,
    required this.onStart,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = ExamTypeInfo.color(exam.type);
    final cardBg = isDark ? const Color(0xFF1F1E1B) : const Color(0xFFFAF9F5);
    final borderColor = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final textColor = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);
    final mutedColor = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);

    final attemptsLeft = exam.maxAttempts > 0
        ? '${exam.maxAttempts - attemptCount} left'
        : null;
    final limitReached = exam.maxAttempts > 0 && attemptCount >= exam.maxAttempts;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Type color bar
                Container(
                  width: 4,
                  height: 44,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(
                    color: typeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: textColor,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _TypeChip(type: exam.type, color: typeColor),
                          const SizedBox(width: 6),
                          _DiffChip(difficulty: exam.difficulty),
                        ],
                      ),
                    ],
                  ),
                ),
                // Three-dot menu
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: mutedColor, size: 20),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        const Icon(Icons.edit_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text('Edit', style: GoogleFonts.inter(fontSize: 14)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFC64545)),
                        const SizedBox(width: 8),
                        Text('Delete', style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFC64545))),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Stats row
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 10, 16, 10),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _StatItem(icon: Icons.quiz_outlined, label: '${exam.questionCount} Q', color: mutedColor),
                if (exam.timeLimit != null)
                  _StatItem(icon: Icons.timer_outlined, label: '${exam.timeLimit}m', color: mutedColor),
                _StatItem(icon: Icons.star_outline_rounded, label: '${exam.totalMarks.toStringAsFixed(0)} pts', color: mutedColor),
                _StatItem(
                  icon: Icons.repeat_rounded,
                  label: attemptCount > 0
                      ? '$attemptCount attempt${attemptCount != 1 ? 's' : ''}${attemptsLeft != null ? ' · $attemptsLeft' : ''}'
                      : attemptsLeft ?? 'Unlimited attempts',
                  color: limitReached ? const Color(0xFFC64545) : mutedColor,
                ),
              ],
            ),
          ),
          // Divider + Start button
          Divider(height: 1, color: borderColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (exam.subjectName != null) ...[
                  Icon(Icons.menu_book_outlined, size: 13, color: mutedColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      exam.subjectName!,
                      style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else const Spacer(),
                FilledButton.icon(
                  onPressed: limitReached ? null : onStart,
                  style: FilledButton.styleFrom(
                    backgroundColor: limitReached ? null : const Color(0xFFCC785C),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text('Start', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  final Color color;
  const _TypeChip({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ExamTypeInfo.icon(type), size: 11, color: color),
          const SizedBox(width: 4),
          Text(ExamTypeInfo.label(type), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _DiffChip extends StatelessWidget {
  final String difficulty;
  const _DiffChip({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final color = switch (difficulty) {
      'easy' => const Color(0xFF5DB872),
      'hard' => const Color(0xFFC64545),
      'mixed' => const Color(0xFFCC785C),
      _ => const Color(0xFFE8A55A),
    };
    final label = difficulty[0].toUpperCase() + difficulty.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatItem({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.inter(fontSize: 12, color: color)),
    ],
  );
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const coral = Color(0xFFCC785C);
    final mutedColor = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final textColor = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('✦', style: GoogleFonts.inter(fontSize: 36, color: coral, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            Text(
              'No exams yet',
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
              'Create your first exam — generate questions\nwith AI or add them manually.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: mutedColor, height: 1.6),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: coral,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text('Create Exam', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
