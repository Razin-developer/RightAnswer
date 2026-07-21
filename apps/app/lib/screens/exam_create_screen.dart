import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/exam.dart';
import '../models/exam_question.dart';
import '../repositories/exam_message_repository.dart';
import '../repositories/exam_question_repository.dart';
import '../repositories/exam_repository.dart';
import '../services/exam_ai_service.dart';
import '../models/app_exception.dart';
import '../widgets/app_feedback.dart';
import '../widgets/chapter_picker.dart';

const _coral = Color(0xFFCC785C);

// ── Screen ────────────────────────────────────────────────────────────────────

class ExamCreateScreen extends StatefulWidget {
  final Exam? exam;
  final List<ExamQuestion>? existingQuestions;

  const ExamCreateScreen({super.key, this.exam, this.existingQuestions});

  @override
  State<ExamCreateScreen> createState() => _ExamCreateScreenState();
}

class _ExamCreateScreenState extends State<ExamCreateScreen> {
  final _examRepo = ExamRepository();
  final _questionRepo = ExamQuestionRepository();
  final _messageRepo = ExamMessageRepository();

  // Settings controllers
  final _nameCtrl = TextEditingController();
  final _questionCountCtrl = TextEditingController(text: '10');
  final _timeLimitCtrl = TextEditingController();
  final _marksPerQCtrl = TextEditingController(text: '1');
  final _passMarkCtrl = TextEditingController(text: '60');
  final _maxAttemptsCtrl = TextEditingController(text: '0');
  final _aiPromptCtrl = TextEditingController();

  String _type = 'mcq';
  String _difficulty = 'medium';
  int _mcqOptionCount = 4;

  // Optional chapter scoping — picked via the shared chapter picker. Null
  // means the AI searches the whole textbook, exactly as before.
  String? _selectedChapterId;
  String? _selectedChapterLabel;

  List<ExamQuestion> _questions = [];
  bool _isGenerating = false;
  bool _settingsExpanded = true;
  bool _isEditing = false; // true = AI refine mode

  Exam? _savedExam;

  @override
  void initState() {
    super.initState();
    if (widget.exam != null) {
      final e = widget.exam!;
      _nameCtrl.text = e.name;
      _questionCountCtrl.text = e.questionCount.toString();
      _timeLimitCtrl.text = e.timeLimit?.toString() ?? '';
      _marksPerQCtrl.text = e.marksPerQuestion.toString();
      _passMarkCtrl.text = e.passMark.toString();
      _maxAttemptsCtrl.text = e.maxAttempts.toString();
      _type = e.type;
      _difficulty = e.difficulty;
      _mcqOptionCount = e.mcqOptionCount;
      _savedExam = e;
      _settingsExpanded = false;
    }
    if (widget.existingQuestions != null) {
      _questions = List.from(widget.existingQuestions!);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _questionCountCtrl.dispose();
    _timeLimitCtrl.dispose();
    _marksPerQCtrl.dispose();
    _passMarkCtrl.dispose();
    _maxAttemptsCtrl.dispose();
    _aiPromptCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  int get _qCount => int.tryParse(_questionCountCtrl.text) ?? 10;
  int? get _timeLimit {
    final v = int.tryParse(_timeLimitCtrl.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  double get _marksPerQ => double.tryParse(_marksPerQCtrl.text) ?? 1.0;
  double get _passMark => double.tryParse(_passMarkCtrl.text) ?? 60.0;
  int get _maxAttempts => int.tryParse(_maxAttemptsCtrl.text) ?? 0;

  Exam _buildExam(String? existingId) {
    final now = DateTime.now();
    return Exam(
      id: existingId ?? const Uuid().v4(),
      name: _nameCtrl.text.trim().isEmpty
          ? 'Untitled Exam'
          : _nameCtrl.text.trim(),
      type: _type,
      questionCount: _questions.isEmpty ? _qCount : _questions.length,
      timeLimit: _timeLimit,
      difficulty: _difficulty,
      mcqOptionCount: _mcqOptionCount,
      marksPerQuestion: _marksPerQ,
      maxAttempts: _maxAttempts,
      passMark: _passMark,
      createdAt: _savedExam?.createdAt ?? now,
      updatedAt: now,
    );
  }

  // ── Chapter scoping ──────────────────────────────────────────────────────

  Future<void> _openChapterPicker() async {
    final result = await showChapterPickerSheet(context);
    if (result == null || !mounted) return;
    setState(() {
      _selectedChapterId = result.chapterId;
      _selectedChapterLabel = result.chapterLabel;
    });
  }

  void _clearSelectedChapter() {
    setState(() {
      _selectedChapterId = null;
      _selectedChapterLabel = null;
    });
  }

  // ── AI Generation ─────────────────────────────────────────────────────────

  Future<void> _generateWithAI() async {
    if (_isGenerating) return;
    if (!AppConfig.hasApiUrl) {
      await AppFeedback.showErrorDialog(
        context,
        AppException.configuration(
          'Missing backend API URL. Add API_URL when building the app.',
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final result = await ExamAIService.instance.generateExam(
        prompt: _aiPromptCtrl.text.trim(),
        type: _type,
        questionCount: _qCount,
        difficulty: _difficulty,
        mcqOptionCount: _mcqOptionCount,
        timeLimit: _timeLimit,
        chapterIds: _selectedChapterId != null ? [_selectedChapterId!] : null,
      );

      // If name not set, use AI-generated title
      if (_nameCtrl.text.trim().isEmpty && result.title.isNotEmpty) {
        _nameCtrl.text = result.title;
      }

      // Assign examId
      _savedExam ??= _buildExam(null);
      final questions = result.questions
          .map(
            (q) => ExamQuestion(
              id: q.id.isEmpty ? const Uuid().v4() : q.id,
              examId: _savedExam!.id,
              questionIndex: q.questionIndex,
              type: q.type,
              question: q.question,
              options: q.options,
              correctAnswer: q.correctAnswer,
              explanation: q.explanation,
              marks: null, // use exam default
              timeLimitSeconds: null,
            ),
          )
          .toList();

      setState(() => _questions = questions);
      await _saveAll();
    } on AppException catch (e) {
      if (mounted) AppFeedback.showErrorDialog(context, e);
    } catch (e) {
      if (mounted) AppFeedback.showToast(context, 'AI generation failed: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _refineWithAI() async {
    if (_isGenerating || _aiPromptCtrl.text.trim().isEmpty) return;
    if (!AppConfig.hasApiUrl) {
      await AppFeedback.showErrorDialog(
        context,
        AppException.configuration(
          'Missing backend API URL. Add API_URL when building the app.',
        ),
      );
      return;
    }
    if (_savedExam == null) {
      AppFeedback.showToast(context, 'Save the exam first');
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final msgs = await _messageRepo.getByExam(_savedExam!.id);
      final result = await ExamAIService.instance.editExam(
        editPrompt: _aiPromptCtrl.text.trim(),
        examType: _type,
        examName: _savedExam!.name,
        currentQuestions: _questions,
        history: msgs,
      );

      final questions = result.questions
          .map(
            (q) => ExamQuestion(
              id: q.id.isEmpty ? const Uuid().v4() : q.id,
              examId: _savedExam!.id,
              questionIndex: q.questionIndex,
              type: q.type,
              question: q.question,
              options: q.options,
              correctAnswer: q.correctAnswer,
              explanation: q.explanation,
              marks: null,
              timeLimitSeconds: null,
            ),
          )
          .toList();

      setState(() {
        _questions = questions;
        _aiPromptCtrl.clear();
      });
      await _saveAll();
    } on AppException catch (e) {
      if (mounted) AppFeedback.showErrorDialog(context, e);
    } catch (e) {
      if (mounted) AppFeedback.showToast(context, 'Refine failed: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _saveAll() async {
    final exam = _buildExam(_savedExam?.id);
    _savedExam = exam;
    if (await _examRepo.getById(exam.id) == null) {
      await _examRepo.insert(exam);
    } else {
      await _examRepo.update(exam);
    }
    await _questionRepo.deleteByExam(exam.id);
    for (final q in _questions) {
      await _questionRepo.insert(q);
    }
    if (mounted) AppFeedback.showToast(context, 'Saved');
  }

  void _addQuestionManually() {
    final examId = _savedExam?.id ?? const Uuid().v4();
    _savedExam ??= _buildExam(examId);
    final q = ExamQuestion(
      id: const Uuid().v4(),
      examId: examId,
      questionIndex: _questions.length,
      type: _type == 'mixed' ? 'mcq' : _type,
      question: '',
      options: _type == 'true_false'
          ? ['True', 'False']
          : _type == 'mcq' || _type == 'mixed'
          ? List.generate(_mcqOptionCount, (i) => '')
          : null,
      correctAnswer: '',
    );
    setState(() => _questions.add(q));
  }

  void _deleteQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
      for (var i = index; i < _questions.length; i++) {
        _questions[i] = ExamQuestion(
          id: _questions[i].id,
          examId: _questions[i].examId,
          questionIndex: i,
          type: _questions[i].type,
          question: _questions[i].question,
          options: _questions[i].options,
          correctAnswer: _questions[i].correctAnswer,
          explanation: _questions[i].explanation,
          marks: _questions[i].marks,
          timeLimitSeconds: _questions[i].timeLimitSeconds,
        );
      }
    });
  }

  void _updateQuestion(int index, ExamQuestion updated) {
    setState(() => _questions[index] = updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFFFAF9F5)
        : const Color(0xFF141413);
    final mutedColor = isDark
        ? const Color(0xFF8E8B82)
        : const Color(0xFF6C6A64);
    final borderColor = isDark
        ? const Color(0xFF2E2C28)
        : const Color(0xFFE6DFD8);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.exam == null ? 'Create Exam' : 'Edit Exam',
          style: GoogleFonts.playfairDisplay(fontSize: 20, letterSpacing: -0.3),
        ),
        actions: [
          if (_questions.isNotEmpty || _savedExam != null)
            TextButton(
              onPressed: _saveAll,
              child: Text(
                'Save',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _coral,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // ── Settings Card ───────────────────────────────────────────────
          _SectionCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () =>
                      setState(() => _settingsExpanded = !_settingsExpanded),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.tune_rounded, size: 18, color: _coral),
                        const SizedBox(width: 8),
                        Text(
                          'Exam Settings',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _settingsExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: mutedColor,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_settingsExpanded) ...[
                  const SizedBox(height: 14),
                  // Name
                  _Label('Exam Name', textColor),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameCtrl,
                    style: GoogleFonts.inter(fontSize: 14, color: textColor),
                    decoration: _inputDec(
                      'e.g. Biology Chapter 3 Quiz',
                      isDark,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Type
                  _Label('Question Type', textColor),
                  const SizedBox(height: 6),
                  _TypeSelector(
                    selected: _type,
                    onChanged: (t) => setState(() => _type = t),
                  ),
                  const SizedBox(height: 14),
                  // Row: count + time
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Questions', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _questionCountCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: textColor,
                              ),
                              decoration: _inputDec('10', isDark),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Time Limit (min)', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _timeLimitCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: textColor,
                              ),
                              decoration: _inputDec('None', isDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Row: marks + pass mark
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Marks / Question', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _marksPerQCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: textColor,
                              ),
                              decoration: _inputDec('1', isDark),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Pass Mark (%)', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _passMarkCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: textColor,
                              ),
                              decoration: _inputDec('60', isDark),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Row: max attempts + difficulty
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Max Attempts (0=∞)', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _maxAttemptsCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: textColor,
                              ),
                              decoration: _inputDec('0', isDark),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Difficulty', textColor),
                            const SizedBox(height: 6),
                            _DifficultyDropdown(
                              value: _difficulty,
                              isDark: isDark,
                              textColor: textColor,
                              onChanged: (v) => setState(() => _difficulty = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_type == 'mcq' || _type == 'mixed') ...[
                    const SizedBox(height: 14),
                    _Label('MCQ Options Count', textColor),
                    const SizedBox(height: 6),
                    Row(
                      children: [3, 4, 5]
                          .map(
                            (n) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  '$n',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                selected: _mcqOptionCount == n,
                                onSelected: (_) =>
                                    setState(() => _mcqOptionCount = n),
                                selectedColor: _coral.withValues(alpha: 0.15),
                                labelStyle: TextStyle(
                                  color: _mcqOptionCount == n
                                      ? _coral
                                      : mutedColor,
                                ),
                                side: BorderSide(
                                  color: _mcqOptionCount == n
                                      ? _coral
                                      : borderColor,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── AI Generation Card ──────────────────────────────────────────
          _SectionCard(
            isDark: isDark,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: _coral),
                    const SizedBox(width: 8),
                    Text(
                      'Generate with AI',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    if (_questions.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _isEditing = !_isEditing),
                        child: Text(
                          _isEditing ? 'Done' : 'Refine',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _coral,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openChapterPicker,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _coral,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.menu_book_outlined, size: 16),
                        label: Text(
                          _selectedChapterLabel ?? 'Scope to a chapter (optional)',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (_selectedChapterLabel != null) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: mutedColor,
                        onPressed: _clearSelectedChapter,
                        tooltip: 'Clear chapter',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _aiPromptCtrl,
                  minLines: 2,
                  maxLines: 4,
                  style: GoogleFonts.inter(fontSize: 14, color: textColor),
                  decoration: _inputDec(
                    _isEditing
                        ? 'Describe how to refine existing questions…'
                        : 'Topic or instructions (e.g. "Photosynthesis, grade 9 level")',
                    isDark,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isGenerating
                            ? null
                            : (_isEditing ? _refineWithAI : _generateWithAI),
                        style: FilledButton.styleFrom(
                          backgroundColor: _coral,
                          disabledBackgroundColor: _coral.withValues(
                            alpha: 0.4,
                          ),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: _isGenerating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text(
                          _isGenerating
                              ? 'Generating…'
                              : _isEditing
                              ? 'Refine Questions'
                              : (_questions.isEmpty
                                    ? 'Generate Questions'
                                    : 'Regenerate'),
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Question List ───────────────────────────────────────────────
          Row(
            children: [
              Text(
                'Questions (${_questions.length})',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addQuestionManually,
                style: TextButton.styleFrom(foregroundColor: _coral),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  'Add',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._questions.asMap().entries.map(
            (e) => _QuestionCard(
              index: e.key,
              question: e.value,
              defaultMarks: _marksPerQ,
              isDark: isDark,
              onUpdate: (q) => _updateQuestion(e.key, q),
              onDelete: () => _deleteQuestion(e.key),
            ),
          ),
          if (_questions.isEmpty)
            _SectionCard(
              isDark: isDark,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      Icon(Icons.quiz_outlined, size: 36, color: mutedColor),
                      const SizedBox(height: 8),
                      Text(
                        'No questions yet.\nGenerate with AI or add manually.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: mutedColor,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      // Bottom save bar
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saveAll,
            style: FilledButton.styleFrom(
              backgroundColor: _coral,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              widget.exam == null ? 'Save Exam' : 'Update Exam',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint, bool isDark) {
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final fill = isDark ? const Color(0xFF181715) : const Color(0xFFFAF9F5);
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        color: isDark ? const Color(0xFF8E8B82) : const Color(0xFF8E8B82),
      ),
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _coral, width: 2),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  final Color textColor;
  const _Label(this.text, this.textColor);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: textColor.withValues(alpha: 0.6),
      letterSpacing: 0.3,
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _SectionCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _TypeSelector({required this.selected, required this.onChanged});

  static const _types = [
    ('mcq', 'MCQ', Icons.radio_button_checked_rounded),
    ('true_false', 'T/F', Icons.toggle_on_rounded),
    ('fill_blank', 'Fill', Icons.text_fields_rounded),
    ('short_answer', 'Short', Icons.short_text_rounded),
    ('long_answer', 'Long', Icons.article_outlined),
    ('mixed', 'Mixed', Icons.auto_awesome_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((t) {
        final isSelected = selected == t.$1;
        return GestureDetector(
          onTap: () => onChanged(t.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? _coral.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? _coral : const Color(0xFFE6DFD8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  t.$3,
                  size: 13,
                  color: isSelected ? _coral : const Color(0xFF8E8B82),
                ),
                const SizedBox(width: 5),
                Text(
                  t.$2,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? _coral : const Color(0xFF8E8B82),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DifficultyDropdown extends StatelessWidget {
  final String value;
  final bool isDark;
  final Color textColor;
  final ValueChanged<String> onChanged;

  const _DifficultyDropdown({
    required this.value,
    required this.isDark,
    required this.textColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final fill = isDark ? const Color(0xFF181715) : const Color(0xFFFAF9F5);
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: fill,
      style: GoogleFonts.inter(fontSize: 14, color: textColor),
      decoration: InputDecoration(
        filled: true,
        fillColor: fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _coral, width: 2),
        ),
      ),
      items: ['easy', 'medium', 'hard', 'mixed']
          .map(
            (d) => DropdownMenuItem(
              value: d,
              child: Text(
                d[0].toUpperCase() + d.substring(1),
                style: GoogleFonts.inter(fontSize: 14, color: textColor),
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ── Question Card ─────────────────────────────────────────────────────────────

class _QuestionCard extends StatefulWidget {
  final int index;
  final ExamQuestion question;
  final double defaultMarks;
  final bool isDark;
  final ValueChanged<ExamQuestion> onUpdate;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.index,
    required this.question,
    required this.defaultMarks,
    required this.isDark,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _expanded = false;
  late TextEditingController _qCtrl;
  late TextEditingController _marksCtrl;
  late TextEditingController _timeCtrl;
  late TextEditingController _answerCtrl;
  late TextEditingController _explCtrl;
  late List<TextEditingController> _optionCtrls;

  @override
  void initState() {
    super.initState();
    final q = widget.question;
    _qCtrl = TextEditingController(text: q.question);
    _marksCtrl = TextEditingController(text: q.marks?.toString() ?? '');
    _timeCtrl = TextEditingController(
      text: q.timeLimitSeconds?.toString() ?? '',
    );
    _answerCtrl = TextEditingController(text: q.correctAnswer);
    _explCtrl = TextEditingController(text: q.explanation ?? '');
    _optionCtrls = (q.options ?? [])
        .map((o) => TextEditingController(text: o))
        .toList();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _marksCtrl.dispose();
    _timeCtrl.dispose();
    _answerCtrl.dispose();
    _explCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    widget.onUpdate(
      widget.question.copyWith(
        question: _qCtrl.text.trim(),
        options: _optionCtrls.isNotEmpty
            ? _optionCtrls.map((c) => c.text.trim()).toList()
            : null,
        correctAnswer: _answerCtrl.text.trim(),
        explanation: _explCtrl.text.trim().isEmpty
            ? null
            : _explCtrl.text.trim(),
        marks: double.tryParse(_marksCtrl.text.trim()),
        timeLimitSeconds: int.tryParse(_timeCtrl.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? const Color(0xFF1F1E1B) : Colors.white;
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final textColor = isDark
        ? const Color(0xFFFAF9F5)
        : const Color(0xFF141413);
    final mutedColor = isDark
        ? const Color(0xFF8E8B82)
        : const Color(0xFF6C6A64);
    final q = widget.question;

    final marksDisplay = q.marks != null
        ? '${q.marks} pts'
        : '${widget.defaultMarks.toStringAsFixed(0)} pts (default)';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _coral.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${widget.index + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _coral,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      q.question.isEmpty ? 'Empty question' : q.question,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: q.question.isEmpty ? mutedColor : textColor,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    marksDisplay,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: _coral,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: mutedColor,
                    size: 20,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    color: const Color(0xFFC64545),
                    onPressed: widget.onDelete,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question text
                  _Label('Question', textColor),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _qCtrl,
                    minLines: 2,
                    maxLines: 5,
                    style: GoogleFonts.inter(fontSize: 13, color: textColor),
                    decoration: _inputDec('Enter question text…', isDark),
                    onChanged: (_) => _save(),
                  ),
                  // Options (MCQ/TF)
                  if (_optionCtrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Label('Options', textColor),
                    const SizedBox(height: 6),
                    ..._optionCtrls.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Text(
                              '${String.fromCharCode(65 + e.key)}. ',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _coral,
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: e.value,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: textColor,
                                ),
                                decoration: _inputDec(
                                  'Option ${String.fromCharCode(65 + e.key)}',
                                  isDark,
                                ),
                                onChanged: (_) => _save(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Correct answer
                  _Label('Correct Answer', textColor),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _answerCtrl,
                    style: GoogleFonts.inter(fontSize: 13, color: textColor),
                    decoration: _inputDec(
                      q.options != null
                          ? 'A, B, C or D'
                          : 'Enter correct answer',
                      isDark,
                    ),
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  // Explanation
                  _Label('Explanation (optional)', textColor),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _explCtrl,
                    minLines: 1,
                    maxLines: 3,
                    style: GoogleFonts.inter(fontSize: 13, color: textColor),
                    decoration: _inputDec(
                      'Why this is the correct answer…',
                      isDark,
                    ),
                    onChanged: (_) => _save(),
                  ),
                  const SizedBox(height: 12),
                  // Marks + time per question
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Marks (override)', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _marksCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: textColor,
                              ),
                              decoration: _inputDec(
                                '${widget.defaultMarks.toStringAsFixed(0)} (default)',
                                isDark,
                              ),
                              onChanged: (_) => _save(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Label('Time Limit (sec)', textColor),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _timeCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: textColor,
                              ),
                              decoration: _inputDec('None', isDark),
                              onChanged: (_) => _save(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _inputDec(String hint, bool isDark) {
    final border = isDark ? const Color(0xFF2E2C28) : const Color(0xFFE6DFD8);
    final fill = isDark ? const Color(0xFF181715) : const Color(0xFFFAF9F5);
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        fontSize: 13,
        color: const Color(0xFF8E8B82),
      ),
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _coral, width: 2),
      ),
      isDense: true,
    );
  }
}
