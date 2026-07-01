import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../models/exam.dart';
import '../models/exam_attempt.dart';
import '../models/exam_question.dart';
import '../repositories/exam_attempt_repository.dart';
import 'exam_result_screen.dart';

const _coral = Color(0xFFCC785C);

class ExamAttemptScreen extends StatefulWidget {
  final Exam exam;
  final List<ExamQuestion> questions;

  const ExamAttemptScreen({super.key, required this.exam, required this.questions});

  @override
  State<ExamAttemptScreen> createState() => _ExamAttemptScreenState();
}

class _ExamAttemptScreenState extends State<ExamAttemptScreen> {
  final _attemptRepo = ExamAttemptRepository();
  final _pageCtrl = PageController();

  int _currentIndex = 0;
  final Map<String, String> _answers = {};
  late final String _attemptId;

  // Global exam timer
  Timer? _globalTimer;
  int _globalSecondsLeft = 0;

  // Per-question timer
  Timer? _questionTimer;
  int _questionSecondsLeft = 0;

  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _attemptId = const Uuid().v4();
    if (widget.exam.timeLimit != null) {
      _globalSecondsLeft = widget.exam.timeLimit! * 60;
      _startGlobalTimer();
    }
    _startQuestionTimer();
  }

  @override
  void dispose() {
    _globalTimer?.cancel();
    _questionTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _startGlobalTimer() {
    _globalTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_globalSecondsLeft <= 0) {
        _globalTimer?.cancel();
        _autoSubmit();
        return;
      }
      setState(() => _globalSecondsLeft--);
    });
  }

  void _startQuestionTimer() {
    _questionTimer?.cancel();
    final q = widget.questions[_currentIndex];
    if (q.timeLimitSeconds != null) {
      _questionSecondsLeft = q.timeLimitSeconds!;
      _questionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_questionSecondsLeft <= 0) {
          _questionTimer?.cancel();
          _nextQuestion();
          return;
        }
        setState(() => _questionSecondsLeft--);
      });
    } else {
      _questionSecondsLeft = 0;
    }
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() => _currentIndex++);
      _pageCtrl.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      _startQuestionTimer();
    }
  }

  void _prevQuestion() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _pageCtrl.animateToPage(_currentIndex,
          duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
      _startQuestionTimer();
    }
  }

  void _setAnswer(String questionId, String answer) {
    setState(() => _answers[questionId] = answer);
  }

  Future<void> _autoSubmit() async {
    if (!_submitted) await _submit();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave exam?', style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: const Text('Your progress will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC64545)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmSubmit() async {
    final answered = _answers.length;
    final total = widget.questions.length;
    if (answered == total) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Submit Exam?', style: GoogleFonts.playfairDisplay(fontSize: 18)),
        content: Text(
          'You have answered $answered of $total questions. '
          'Unanswered questions will count as incorrect.',
          style: GoogleFonts.inter(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continue')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _coral),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _submit() async {
    if (_submitted) return;
    _submitted = true;
    _globalTimer?.cancel();
    _questionTimer?.cancel();

    // Score calculation
    double score = 0;
    double totalMarks = 0;
    for (final q in widget.questions) {
      final qMarks = q.marks ?? widget.exam.marksPerQuestion;
      totalMarks += qMarks;
      final userAnswer = _answers[q.id]?.trim().toLowerCase();
      if (userAnswer != null && userAnswer == q.correctAnswer.trim().toLowerCase()) {
        score += qMarks;
      }
    }
    final percentage = totalMarks > 0 ? (score / totalMarks) * 100 : 0;
    final isPassed = percentage >= widget.exam.passMark;

    final attempt = ExamAttempt(
      id: _attemptId,
      examId: widget.exam.id,
      startedAt: DateTime.now(),
      completedAt: DateTime.now(),
      answers: Map.from(_answers),
      score: score,
      totalMarks: totalMarks,
      isPassed: isPassed,
    );

    await _attemptRepo.insert(attempt);

    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => ExamResultScreen(
          exam: widget.exam,
          questions: widget.questions,
          attempt: attempt,
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);
    final mutedColor = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final bg = isDark ? const Color(0xFF181715) : const Color(0xFFFAF9F5);

    final answered = _answers.length;
    final total = widget.questions.length;
    final progress = total > 0 ? answered / total : 0.0;

    // Timer color
    final timerColor = _globalSecondsLeft < 60 && widget.exam.timeLimit != null
        ? const Color(0xFFC64545)
        : _coral;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        leading: BackButton(onPressed: _confirmLeave),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.exam.name,
              style: GoogleFonts.playfairDisplay(fontSize: 16, color: textColor, letterSpacing: -0.2),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${_currentIndex + 1} / $total  ·  $answered answered',
              style: GoogleFonts.inter(fontSize: 11, color: mutedColor),
            ),
          ],
        ),
        actions: [
          if (widget.exam.timeLimit != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: timerColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_outlined, size: 14, color: timerColor),
                    const SizedBox(width: 4),
                    Text(_formatTime(_globalSecondsLeft),
                      style: GoogleFonts.jetBrainsMono(fontSize: 13, color: timerColor, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          TextButton(
            onPressed: () async {
              if (await _confirmSubmit()) _submit();
            },
            child: Text('Submit', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _coral)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8),
            valueColor: const AlwaysStoppedAnimation(_coral),
            minHeight: 3,
          ),
        ),
      ),
      body: Column(
        children: [
          // Question pages
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: total,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => _QuestionView(
                question: widget.questions[i],
                index: i,
                answer: _answers[widget.questions[i].id],
                isDark: isDark,
                questionSecondsLeft: i == _currentIndex
                    ? (widget.questions[i].timeLimitSeconds != null ? _questionSecondsLeft : null)
                    : null,
                onAnswer: (ans) => _setAnswer(widget.questions[i].id, ans),
              ),
            ),
          ),
          // Navigation bar
          Container(
            color: isDark ? const Color(0xFF1F1E1B) : Colors.white,
            padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
            child: Row(children: [
              OutlinedButton.icon(
                onPressed: _currentIndex > 0 ? _prevQuestion : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _coral,
                  side: const BorderSide(color: _coral),
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: Text('Prev', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              // Question dots navigator
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(total, (i) {
                      final isAnswered = _answers.containsKey(widget.questions[i].id);
                      final isCurrent = i == _currentIndex;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _currentIndex = i);
                          _pageCtrl.animateToPage(i,
                              duration: const Duration(milliseconds: 200), curve: Curves.easeInOut);
                          _startQuestionTimer();
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? _coral
                                : isAnswered
                                ? _coral.withValues(alpha: 0.2)
                                : isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${i + 1}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isCurrent ? Colors.white : isAnswered ? _coral : mutedColor,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _currentIndex < total - 1
                    ? _nextQuestion
                    : () async { if (await _confirmSubmit()) _submit(); },
                style: FilledButton.styleFrom(
                  backgroundColor: _coral,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: Icon(
                  _currentIndex < total - 1 ? Icons.arrow_forward_rounded : Icons.check_rounded,
                  size: 18,
                ),
                label: Text(
                  _currentIndex < total - 1 ? 'Next' : 'Finish',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Question View ─────────────────────────────────────────────────────────────

class _QuestionView extends StatelessWidget {
  final ExamQuestion question;
  final int index;
  final String? answer;
  final bool isDark;
  final int? questionSecondsLeft;
  final ValueChanged<String> onAnswer;

  const _QuestionView({
    required this.question,
    required this.index,
    required this.answer,
    required this.isDark,
    required this.questionSecondsLeft,
    required this.onAnswer,
  });

  String _formatTime(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);
    final mutedColor = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final cardBg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);

    Widget answerWidget;
    final opts = question.options;

    if (opts != null) {
      // MCQ or T/F — option tiles
      answerWidget = Column(
        children: opts.asMap().entries.map((e) {
          final letter = String.fromCharCode(65 + e.key);
          final isSelected = answer == e.value || answer == letter;
          return GestureDetector(
            onTap: () => onAnswer(e.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isSelected ? _coral.withValues(alpha: 0.1) : cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSelected ? _coral : border, width: isSelected ? 2 : 1),
              ),
              child: Row(children: [
                Container(
                  width: 28, height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? _coral : isDark ? const Color(0xFF2E2C28) : const Color(0xFFEFE9DE),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(letter,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : mutedColor)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(e.value,
                  style: GoogleFonts.inter(fontSize: 14, color: textColor, height: 1.4))),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: _coral, size: 18),
              ]),
            ),
          );
        }).toList(),
      );
    } else {
      // Text input
      answerWidget = TextField(
        minLines: question.type == 'long_answer' ? 4 : 1,
        maxLines: question.type == 'long_answer' ? 8 : 3,
        onChanged: onAnswer,
        controller: TextEditingController(text: answer)..selection = TextSelection.collapsed(offset: answer?.length ?? 0),
        style: GoogleFonts.inter(fontSize: 14, color: textColor),
        decoration: InputDecoration(
          hintText: question.type == 'fill_blank' ? 'Fill in the blank…' : 'Type your answer…',
          hintStyle: GoogleFonts.inter(fontSize: 14, color: mutedColor),
          filled: true,
          fillColor: cardBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _coral, width: 2)),
          contentPadding: const EdgeInsets.all(14),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Q header
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _coral.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Q${index + 1}',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: _coral)),
            ),
            const SizedBox(width: 8),
            Text(
              '${(question.marks ?? 1).toStringAsFixed(0)} pts',
              style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
            ),
            if (questionSecondsLeft != null) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: questionSecondsLeft! < 10 ? const Color(0xFFC64545).withValues(alpha: 0.1) : _coral.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_outlined, size: 12,
                    color: questionSecondsLeft! < 10 ? const Color(0xFFC64545) : _coral),
                  const SizedBox(width: 4),
                  Text(_formatTime(questionSecondsLeft!),
                    style: GoogleFonts.jetBrainsMono(fontSize: 12,
                      color: questionSecondsLeft! < 10 ? const Color(0xFFC64545) : _coral)),
                ]),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          // Question text
          Text(
            question.question,
            style: GoogleFonts.inter(fontSize: 16, color: textColor, height: 1.6, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 20),
          // Answer widget
          answerWidget,
        ],
      ),
    );
  }
}
