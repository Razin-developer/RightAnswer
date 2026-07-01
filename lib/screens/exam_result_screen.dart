import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/exam.dart';
import '../models/exam_attempt.dart';
import '../models/exam_question.dart';

const _coral = Color(0xFFCC785C);

class ExamResultScreen extends StatefulWidget {
  final Exam exam;
  final List<ExamQuestion> questions;
  final ExamAttempt attempt;

  const ExamResultScreen({
    super.key,
    required this.exam,
    required this.questions,
    required this.attempt,
  });

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  bool _showReview = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);
    final mutedColor = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final bg = isDark ? const Color(0xFF181715) : const Color(0xFFFAF9F5);

    final attempt = widget.attempt;
    final pct = attempt.percentage;
    final isPassed = attempt.isPassed;
    final passColor = isPassed ? const Color(0xFF5DB872) : const Color(0xFFC64545);
    final passLabel = isPassed ? 'Passed' : 'Failed';

    int correct = 0;
    int wrong = 0;
    int skipped = 0;
    for (final q in widget.questions) {
      final userAnswer = attempt.answers[q.id];
      if (userAnswer == null || userAnswer.isEmpty) {
        skipped++;
      } else if (userAnswer.trim().toLowerCase() == q.correctAnswer.trim().toLowerCase()) {
        correct++;
      } else {
        wrong++;
      }
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        automaticallyImplyLeading: false,
        title: Text('Results', style: GoogleFonts.playfairDisplay(fontSize: 20, color: textColor, letterSpacing: -0.3)),
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst || r.settings.name == '/main'),
            child: Text('Done', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: _coral)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Score card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F1E1B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8)),
            ),
            child: Column(
              children: [
                // Pass/Fail badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: passColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      isPassed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      size: 16, color: passColor,
                    ),
                    const SizedBox(width: 6),
                    Text(passLabel,
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: passColor)),
                  ]),
                ),
                const SizedBox(height: 20),
                // Score circle
                SizedBox(
                  width: 120, height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 120, height: 120,
                        child: CircularProgressIndicator(
                          value: pct / 100,
                          strokeWidth: 10,
                          backgroundColor: isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8),
                          valueColor: AlwaysStoppedAnimation(passColor),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: GoogleFonts.playfairDisplay(fontSize: 28, fontWeight: FontWeight.w400, color: textColor, letterSpacing: -0.5),
                        ),
                        Text(
                          '${attempt.score.toStringAsFixed(0)} / ${attempt.totalMarks.toStringAsFixed(0)}',
                          style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.exam.name,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(fontSize: 16, color: textColor, letterSpacing: -0.2),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pass mark: ${widget.exam.passMark.toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(fontSize: 12, color: mutedColor),
                ),
                const SizedBox(height: 20),
                // Stats row
                Row(children: [
                  _StatBox(value: correct.toString(), label: 'Correct', color: const Color(0xFF5DB872), isDark: isDark),
                  const SizedBox(width: 8),
                  _StatBox(value: wrong.toString(), label: 'Wrong', color: const Color(0xFFC64545), isDark: isDark),
                  const SizedBox(width: 8),
                  _StatBox(value: skipped.toString(), label: 'Skipped', color: mutedColor, isDark: isDark),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Review toggle
          InkWell(
            onTap: () => setState(() => _showReview = !_showReview),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1E1B) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8)),
              ),
              child: Row(children: [
                Icon(Icons.rate_review_outlined, size: 18, color: _coral),
                const SizedBox(width: 8),
                Text('Review Answers', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
                const Spacer(),
                Icon(_showReview ? Icons.expand_less : Icons.expand_more, color: mutedColor),
              ]),
            ),
          ),
          if (_showReview) ...[
            const SizedBox(height: 8),
            ...widget.questions.asMap().entries.map((e) => _ReviewCard(
              index: e.key,
              question: e.value,
              userAnswer: attempt.answers[e.value.id],
              isDark: isDark,
            )),
          ],
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _StatBox({required this.value, required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          Text(value, style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w400, color: color)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: color.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final int index;
  final ExamQuestion question;
  final String? userAnswer;
  final bool isDark;

  const _ReviewCard({
    required this.index,
    required this.question,
    required this.userAnswer,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413);
    final mutedColor = isDark ? const Color(0xFF8E8B82) : const Color(0xFF6C6A64);
    final bg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);

    final isCorrect = userAnswer != null &&
        userAnswer!.trim().toLowerCase() == question.correctAnswer.trim().toLowerCase();
    final isSkipped = userAnswer == null || userAnswer!.isEmpty;

    final statusColor = isSkipped
        ? mutedColor
        : isCorrect ? const Color(0xFF5DB872) : const Color(0xFFC64545);
    final statusIcon = isSkipped
        ? Icons.remove_circle_outline_rounded
        : isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('Q${index + 1}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _coral)),
            const SizedBox(width: 8),
            Icon(statusIcon, size: 16, color: statusColor),
            const SizedBox(width: 4),
            Text(
              isSkipped ? 'Skipped' : isCorrect ? 'Correct' : 'Incorrect',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
            ),
          ]),
          const SizedBox(height: 8),
          Text(question.question,
            style: GoogleFonts.inter(fontSize: 13, color: textColor, height: 1.5)),
          if (!isSkipped && !isCorrect) ...[
            const SizedBox(height: 8),
            _AnswerRow(label: 'Your answer', value: userAnswer!, color: const Color(0xFFC64545), isDark: isDark),
          ],
          const SizedBox(height: 6),
          _AnswerRow(label: 'Correct', value: question.correctAnswer, color: const Color(0xFF5DB872), isDark: isDark),
          if (question.explanation != null && question.explanation!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _coral.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: _coral, width: 3)),
              ),
              child: Text(question.explanation!,
                style: GoogleFonts.inter(fontSize: 12, color: mutedColor, height: 1.5, fontStyle: FontStyle.italic)),
            ),
          ],
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isDark;

  const _AnswerRow({required this.label, required this.value, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(value,
          style: GoogleFonts.inter(fontSize: 13, color: isDark ? const Color(0xFFFAF9F5) : const Color(0xFF141413), height: 1.4)),
      ),
    ]);
  }
}
