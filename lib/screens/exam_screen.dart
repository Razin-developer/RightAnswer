import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/chapter.dart';
import '../models/exam.dart';
import '../models/exam_message.dart';
import '../models/exam_question.dart';
import '../models/subject.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/exam_message_repository.dart';
import '../repositories/exam_question_repository.dart';
import '../repositories/exam_repository.dart';
import '../repositories/subject_repository.dart';
import '../services/exam_ai_service.dart';
import '../models/app_exception.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_logo.dart';
import '../widgets/voice_input_sheet.dart';
import 'settings_screen.dart';

// ── Type helpers ─────────────────────────────────────────────────────────────

class _ET {
  static const all = [
    'mcq',
    'true_false',
    'fill_blank',
    'short_answer',
    'long_answer',
    'mixed',
  ];

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

  static Color color(String t, ColorScheme cs) => switch (t) {
    'mcq' => cs.primary,
    'true_false' => Colors.teal,
    'fill_blank' => Colors.orange,
    'short_answer' => Colors.purple,
    'long_answer' => Colors.indigo,
    'mixed' => Colors.pink,
    _ => cs.primary,
  };
}

// ── Exam config ───────────────────────────────────────────────────────────────

class _ExamConfig {
  int questionCount;
  int? timeLimit;
  String difficulty;
  int mcqOptionCount;

  _ExamConfig({
    this.questionCount = 10,
    this.timeLimit,
    this.difficulty = 'medium',
    this.mcqOptionCount = 4,
  });
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

  Exam? _currentExam;
  List<ExamQuestion> _questions = [];
  List<ExamMessage> _editMessages = [];
  List<Exam> _allExams = [];

  final _createCtrl = TextEditingController();
  final _editCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _editScrollCtrl = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _isGenerating = false;
  bool _isEditing = false;
  bool _isRecording = false;

  String? _imagePath;
  String? _editImagePath;
  String _selectedType = 'mcq';

  String? _contextSubjectId;
  String? _contextSubjectName;
  List<String> _contextChapterIds = [];
  List<String> _contextChapterNames = [];

  @override
  void initState() {
    super.initState();
    _loadAllExams();
  }

  @override
  void dispose() {
    _createCtrl.dispose();
    _editCtrl.dispose();
    _scrollCtrl.dispose();
    _editScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllExams() async {
    final exams = await _examRepo.getAll();
    if (mounted) setState(() => _allExams = exams);
  }

  Future<void> _loadExam(Exam exam) async {
    final questions = await _questionRepo.getByExam(exam.id);
    final messages = await _messageRepo.getByExam(exam.id);
    if (mounted) {
      setState(() {
        _currentExam = exam;
        _questions = questions;
        _editMessages = messages;
      });
    }
  }

  void _startNewExam() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    setState(() {
      _currentExam = null;
      _questions = [];
      _editMessages = [];
      _createCtrl.clear();
      _imagePath = null;
      _isGenerating = false;
    });
  }

  // ── Create flow ──────────────────────────────────────────────────────────

  Future<void> _onSendCreate() async {
    if (_isGenerating) return;
    if (!AppConfig.hasOpenAiApiKey) {
      await AppFeedback.showErrorDialog(
        context,
        AppException.configuration(
          'Build is missing OPENAI_API_KEY. Run with --dart-define=OPENAI_API_KEY=your_key.',
        ),
      );
      return;
    }

    final prompt = _createCtrl.text.trim();
    final config = await _showConfigDialog(context, _selectedType);
    if (config == null) return;

    setState(() => _isGenerating = true);

    try {
      final result = await ExamAIService.instance.generateExam(
        prompt: prompt,
        type: _selectedType,
        questionCount: config.questionCount,
        difficulty: config.difficulty,
        mcqOptionCount: config.mcqOptionCount,
        timeLimit: config.timeLimit,
        subjectName: _contextSubjectName,
        chapterIds: _contextChapterIds,
        imagePath: _imagePath,
      );

      final now = DateTime.now();
      final examId = const Uuid().v4();
      final examName = result.title.isNotEmpty
          ? result.title
          : await ExamAIService.instance.generateExamName(
              prompt,
              _selectedType,
            );

      final exam = Exam(
        id: examId,
        name: examName,
        type: _selectedType,
        subjectId: _contextSubjectId,
        subjectName: _contextSubjectName,
        chapterIds: _contextChapterIds,
        chapterNames: _contextChapterNames,
        questionCount: result.questions.length,
        timeLimit: config.timeLimit,
        difficulty: config.difficulty,
        mcqOptionCount: config.mcqOptionCount,
        createdAt: now,
        updatedAt: now,
      );

      final questions = result.questions.map((q) {
        q = ExamQuestion(
          id: q.id,
          examId: examId,
          questionIndex: q.questionIndex,
          type: q.type,
          question: q.question,
          options: q.options,
          correctAnswer: q.correctAnswer,
          explanation: q.explanation,
        );
        return q;
      }).toList();

      await _examRepo.insert(exam);
      await _questionRepo.insertAll(questions);

      // Store the initial user prompt as first message
      if (prompt.isNotEmpty) {
        final userMsg = ExamMessage(
          id: const Uuid().v4(),
          examId: examId,
          role: 'user',
          content: prompt,
          imagePath: _imagePath,
          createdAt: DateTime.now(),
        );
        await _messageRepo.insert(userMsg);
      }

      await _loadAllExams();
      if (mounted) {
        setState(() {
          _currentExam = exam;
          _questions = questions;
          _editMessages = prompt.isNotEmpty
              ? [
                  ExamMessage(
                    id: const Uuid().v4(),
                    examId: examId,
                    role: 'user',
                    content: prompt,
                    imagePath: _imagePath,
                    createdAt: DateTime.now(),
                  ),
                ]
              : [];
          _createCtrl.clear();
          _imagePath = null;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        await AppFeedback.showErrorDialog(context, e);
      }
    }
  }

  // ── Edit flow ─────────────────────────────────────────────────────────────

  Future<void> _onSendEdit() async {
    if (_currentExam == null || _isEditing) return;
    final prompt = _editCtrl.text.trim();
    if (prompt.isEmpty && _editImagePath == null) return;

    setState(() => _isEditing = true);

    // Optimistically add user message
    final userMsg = ExamMessage(
      id: const Uuid().v4(),
      examId: _currentExam!.id,
      role: 'user',
      content: prompt,
      imagePath: _editImagePath,
      createdAt: DateTime.now(),
    );
    await _messageRepo.insert(userMsg);
    setState(() {
      _editMessages = [..._editMessages, userMsg];
      _editCtrl.clear();
      _editImagePath = null;
    });
    _scrollEditToBottom();

    try {
      final result = await ExamAIService.instance.editExam(
        editPrompt: prompt,
        examType: _currentExam!.type,
        examName: _currentExam!.name,
        currentQuestions: _questions,
        history: _editMessages,
        imagePath: _editImagePath,
        subjectName: _currentExam!.subjectName,
        chapterIds: _currentExam!.chapterIds,
      );

      final examId = _currentExam!.id;
      final updatedQuestions = result.questions
          .map(
            (q) => ExamQuestion(
              id: const Uuid().v4(),
              examId: examId,
              questionIndex: q.questionIndex,
              type: q.type,
              question: q.question,
              options: q.options,
              correctAnswer: q.correctAnswer,
              explanation: q.explanation,
            ),
          )
          .toList();

      await _questionRepo.deleteByExam(examId);
      await _questionRepo.insertAll(updatedQuestions);

      final title = result.title.isNotEmpty ? result.title : _currentExam!.name;
      await _examRepo.update(
        _currentExam!.copyWith(
          name: title,
          questionCount: updatedQuestions.length,
          updatedAt: DateTime.now(),
        ),
      );

      final assistantMsg = ExamMessage(
        id: const Uuid().v4(),
        examId: examId,
        role: 'assistant',
        content:
            'Updated the exam: now ${updatedQuestions.length} question${updatedQuestions.length == 1 ? '' : 's'}.',
        createdAt: DateTime.now(),
      );
      await _messageRepo.insert(assistantMsg);

      await _loadAllExams();
      if (mounted) {
        setState(() {
          _currentExam = _currentExam!.copyWith(
            name: title,
            questionCount: updatedQuestions.length,
            updatedAt: DateTime.now(),
          );
          _questions = updatedQuestions;
          _editMessages = [..._editMessages, assistantMsg];
          _isEditing = false;
        });
        _scrollEditToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isEditing = false);
        await AppFeedback.showErrorDialog(context, e);
      }
    }
  }

  // ── Question inline edit ──────────────────────────────────────────────────

  Future<void> _saveQuestionEdit(ExamQuestion updated) async {
    await _questionRepo.update(updated);
    final idx = _questions.indexWhere((q) => q.id == updated.id);
    if (idx >= 0 && mounted) {
      setState(() => _questions[idx] = updated);
    }
  }

  Future<void> _deleteQuestion(ExamQuestion q) async {
    await _questionRepo.delete(q.id);
    if (!mounted) return;
    setState(() {
      _questions.removeWhere((x) => x.id == q.id);
      // Re-index
      for (int i = 0; i < _questions.length; i++) {
        _questions[i] = ExamQuestion(
          id: _questions[i].id,
          examId: _questions[i].examId,
          questionIndex: i,
          type: _questions[i].type,
          question: _questions[i].question,
          options: _questions[i].options,
          correctAnswer: _questions[i].correctAnswer,
          explanation: _questions[i].explanation,
          userAnswer: _questions[i].userAnswer,
        );
      }
    });
    await _examRepo.update(
      _currentExam!.copyWith(questionCount: _questions.length),
    );
  }

  // ── Rename & Delete exam ──────────────────────────────────────────────────

  Future<void> _renameExam() async {
    if (_currentExam == null) return;
    final ctrl = TextEditingController(text: _currentExam!.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Exam'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Exam name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    await _examRepo.updateName(_currentExam!.id, result);
    await _loadAllExams();
    if (mounted) {
      setState(() => _currentExam = _currentExam!.copyWith(name: result));
    }
  }

  Future<void> _deleteExam({Exam? exam}) async {
    final target = exam ?? _currentExam;
    if (target == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Exam'),
        content: Text('Delete "${target.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _examRepo.delete(target.id);
    await _loadAllExams();
    if (mounted && (_currentExam?.id == target.id)) {
      setState(() {
        _currentExam = null;
        _questions = [];
        _editMessages = [];
      });
    }
  }

  // ── Voice ─────────────────────────────────────────────────────────────────

  Future<void> _toggleVoice(bool forEdit) async => _openVoiceComposer(forEdit);

  // ── Image ─────────────────────────────────────────────────────────────────

  Future<void> _openVoiceComposer(bool forEdit) async {
    if (_isGenerating) return;
    setState(() => _isRecording = true);
    final spoken = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => VoiceInputSheet(
        title: forEdit ? 'Edit with Voice' : 'Create with Voice',
        initialText: (forEdit ? _editCtrl.text : _createCtrl.text).trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _isRecording = false);
    if (spoken == null || spoken.trim().isEmpty) return;
    final controller = forEdit ? _editCtrl : _createCtrl;
    controller.text = spoken.trim();
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
  }

  Future<void> _pickImage(ImageSource source, {required bool forEdit}) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file != null && mounted) {
      setState(() {
        if (forEdit) {
          _editImagePath = file.path;
        } else {
          _imagePath = file.path;
        }
      });
    }
  }

  void _showImagePicker(BuildContext ctx, {required bool forEdit}) {
    showModalBottomSheet(
      context: ctx,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(c);
                _pickImage(ImageSource.gallery, forEdit: forEdit);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(c);
                _pickImage(ImageSource.camera, forEdit: forEdit);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Config dialog ─────────────────────────────────────────────────────────

  Future<_ExamConfig?> _showConfigDialog(BuildContext ctx, String type) async {
    final config = _ExamConfig();
    return showDialog<_ExamConfig>(
      context: ctx,
      builder: (dCtx) => _ExamConfigDialog(config: config, type: type),
    );
  }

  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollEditToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_editScrollCtrl.hasClients) {
        _editScrollCtrl.animateTo(
          _editScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: _buildAppBar(),
      drawer: _ExamDrawer(
        allExams: _allExams,
        currentExamId: _currentExam?.id,
        onSelectExam: (exam) {
          _scaffoldKey.currentState?.closeDrawer();
          _loadExam(exam);
        },
        onNewExam: () {
          _scaffoldKey.currentState?.closeDrawer();
          _startNewExam();
        },
        onDeleteExam: _deleteExam,
      ),
      body: _currentExam == null ? _buildCreateBody() : _buildExamBody(),
    );
  }

  AppBar _buildAppBar() {
    final theme = Theme.of(context);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: _currentExam == null
          ? const Text('Exams', style: TextStyle(fontWeight: FontWeight.w700))
          : GestureDetector(
              onTap: _renameExam,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentExam!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        _ET.icon(_currentExam!.type),
                        size: 11,
                        color: _ET.color(_currentExam!.type, theme.colorScheme),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _ET.label(_currentExam!.type),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                      if (_currentExam!.timeLimit != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.timer_outlined,
                          size: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.45,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${_currentExam!.timeLimit} min',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
      actions: [
        if (_currentExam != null) ...[
          IconButton(
            icon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
            tooltip: 'Rename',
            onPressed: _renameExam,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            tooltip: 'Delete exam',
            onPressed: () => _deleteExam(),
          ),
        ],
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    );
  }

  // ── Create body ───────────────────────────────────────────────────────────

  Widget _buildCreateBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeCard(),
                const SizedBox(height: 20),
                _ContextBar(
                  subjectName: _contextSubjectName,
                  chapterNames: _contextChapterNames,
                  onClear: () => setState(() {
                    _contextSubjectId = null;
                    _contextSubjectName = null;
                    _contextChapterIds = [];
                    _contextChapterNames = [];
                  }),
                  onTap: () => _showContextSheet(),
                ),
                const SizedBox(height: 14),
                _buildTypeRow(),
              ],
            ),
          ),
        ),
        _buildCreateInput(),
      ],
    );
  }

  Widget _buildWelcomeCard() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.quiz_rounded,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Exam Generator',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Select a type, optionally add a chapter for context, then describe what you want.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeRow() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUESTION TYPE',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _ET.all.map((t) {
            final selected = _selectedType == t;
            final color = _ET.color(t, theme.colorScheme);
            return GestureDetector(
              onTap: () => setState(() => _selectedType = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.15)
                      : theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? color : theme.dividerColor,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _ET.icon(t),
                      size: 14,
                      color: selected
                          ? color
                          : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _ET.label(t),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: selected
                            ? color
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCreateInput() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image preview
          if (_imagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ImagePreview(
                path: _imagePath!,
                onRemove: () => setState(() => _imagePath = null),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Image pick
              IconButton(
                icon: Icon(
                  Icons.image_outlined,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: () => _showImagePicker(context, forEdit: false),
              ),
              // Input field
              Expanded(
                child: TextField(
                  controller: _createCtrl,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Describe what to examine, or just send…',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Voice
              IconButton(
                icon: Icon(
                  _isRecording ? Icons.stop_circle_rounded : Icons.mic_outlined,
                  color: _isRecording
                      ? Colors.red
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: () => _toggleVoice(false),
              ),
              // Send
              if (_isGenerating)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else
                FilledButton(
                  onPressed: _onSendCreate,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.all(10),
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Exam body ─────────────────────────────────────────────────────────────

  Widget _buildExamBody() {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Stats bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: theme.colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              _StatChip(
                icon: Icons.format_list_numbered_rounded,
                label: '${_questions.length} Qs',
              ),
              if (_currentExam!.timeLimit != null) ...[
                const SizedBox(width: 12),
                _StatChip(
                  icon: Icons.timer_outlined,
                  label: '${_currentExam!.timeLimit} min',
                ),
              ],
              const SizedBox(width: 12),
              _StatChip(
                icon: Icons.signal_cellular_alt_rounded,
                label:
                    _currentExam!.difficulty[0].toUpperCase() +
                    _currentExam!.difficulty.substring(1),
              ),
              const Spacer(),
              Text(
                _currentExam!.chapterNames.isEmpty
                    ? 'No context'
                    : _currentExam!.chapterNames.join(', '),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  overflow: TextOverflow.ellipsis,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              // Questions
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                sliver: SliverList.builder(
                  itemCount: _questions.length,
                  itemBuilder: (ctx, i) => _QuestionCard(
                    question: _questions[i],
                    index: i,
                    onSave: _saveQuestionEdit,
                    onDelete: () => _deleteQuestion(_questions[i]),
                  ),
                ),
              ),
              // Edit chat section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
                  child: _buildEditSectionHeader(),
                ),
              ),
              // Messages
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                sliver: SliverList.builder(
                  itemCount: _editMessages.length,
                  itemBuilder: (ctx, i) =>
                      _EditMessageBubble(msg: _editMessages[i]),
                ),
              ),
              if (_isEditing)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _TypingIndicator(),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
        _buildEditInput(),
      ],
    );
  }

  Widget _buildEditSectionHeader() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Divider(color: theme.dividerColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Refine with AI',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Divider(color: theme.dividerColor)),
      ],
    );
  }

  Widget _buildEditInput() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_editImagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ImagePreview(
                path: _editImagePath!,
                onRemove: () => setState(() => _editImagePath = null),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  Icons.image_outlined,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: () => _showImagePicker(context, forEdit: true),
              ),
              Expanded(
                child: TextField(
                  controller: _editCtrl,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Add, remove, or change questions…',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(
                  _isRecording ? Icons.stop_circle_rounded : Icons.mic_outlined,
                  color: _isRecording
                      ? Colors.red
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                onPressed: () => _toggleVoice(true),
              ),
              if (_isEditing)
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else
                FilledButton(
                  onPressed:
                      (_editCtrl.text.trim().isNotEmpty ||
                          _editImagePath != null)
                      ? _onSendEdit
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(40, 40),
                    padding: const EdgeInsets.all(10),
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(Icons.send_rounded, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Context sheet ─────────────────────────────────────────────────────────

  void _showContextSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ContextSelectorSheet(
        selectedSubjectId: _contextSubjectId,
        selectedChapterIds: _contextChapterIds,
        onConfirm: (sId, sName, cIds, cNames) {
          setState(() {
            _contextSubjectId = sId;
            _contextSubjectName = sName;
            _contextChapterIds = cIds;
            _contextChapterNames = cNames;
          });
        },
      ),
    );
  }
}

// ── Exam Drawer ───────────────────────────────────────────────────────────────

class _ExamDrawer extends StatelessWidget {
  final List<Exam> allExams;
  final String? currentExamId;
  final void Function(Exam) onSelectExam;
  final VoidCallback onNewExam;
  final void Function({Exam? exam}) onDeleteExam;

  const _ExamDrawer({
    required this.allExams,
    required this.currentExamId,
    required this.onSelectExam,
    required this.onNewExam,
    required this.onDeleteExam,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group by type
    final groups = <String, List<Exam>>{};
    for (final e in allExams) {
      (groups[e.type] ??= []).add(e);
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
              child: Row(
                children: [
                  const AppLogo(size: 32),
                  const SizedBox(width: 10),
                  Text(
                    'RightAnswer',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: InkWell(
                onTap: onNewExam,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'New Exam',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(
              height: 24,
              indent: 12,
              endIndent: 12,
              color: theme.dividerColor,
            ),
            Expanded(
              child: allExams.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        'No exams yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 8),
                      children: groups.entries.map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                _ET.label(entry.key).toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                            ),
                            ...entry.value.map((exam) {
                              final selected = exam.id == currentExamId;
                              return InkWell(
                                onTap: () => onSelectExam(exam),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 1,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? theme.colorScheme.primary.withValues(
                                            alpha: 0.1,
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              exam.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: selected
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                                color: selected
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                          .colorScheme
                                                          .onSurface
                                                          .withValues(
                                                            alpha: 0.85,
                                                          ),
                                              ),
                                            ),
                                            Text(
                                              '${exam.questionCount} questions',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: theme
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.45),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        onTap: () => onDeleteExam(exam: exam),
                                        child: Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Question Card ─────────────────────────────────────────────────────────────

class _QuestionCard extends StatefulWidget {
  final ExamQuestion question;
  final int index;
  final void Function(ExamQuestion updated) onSave;
  final VoidCallback onDelete;

  const _QuestionCard({
    required this.question,
    required this.index,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  bool _showAnswer = false;
  bool _isEditing = false;
  String? _selectedOption;

  late final TextEditingController _qCtrl;
  late final TextEditingController _aCtrl;
  late final TextEditingController _eCtrl;
  late List<TextEditingController> _optCtrls;

  @override
  void initState() {
    super.initState();
    _qCtrl = TextEditingController(text: widget.question.question);
    _aCtrl = TextEditingController(text: widget.question.correctAnswer);
    _eCtrl = TextEditingController(text: widget.question.explanation ?? '');
    _optCtrls = (widget.question.options ?? [])
        .map((o) => TextEditingController(text: o))
        .toList();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _aCtrl.dispose();
    _eCtrl.dispose();
    for (final c in _optCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _saveEdit() {
    final updated = widget.question.copyWith(
      question: _qCtrl.text.trim(),
      options: _optCtrls.isNotEmpty
          ? _optCtrls.map((c) => c.text.trim()).toList()
          : null,
      correctAnswer: _aCtrl.text.trim(),
      explanation: _eCtrl.text.trim().isEmpty ? null : _eCtrl.text.trim(),
    );
    widget.onSave(updated);
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;
    final typeColor = _ET.color(q.type, theme.colorScheme);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${widget.index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: typeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _ET.label(q.type),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: typeColor,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isEditing ? Icons.close_rounded : Icons.edit_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                  onPressed: () => setState(() => _isEditing = !_isEditing),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Question'),
                        content: const Text('Remove this question?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) widget.onDelete();
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // Edit mode
          if (_isEditing)
            _buildEditMode(theme)
          else
            _buildViewMode(theme, q, typeColor),
        ],
      ),
    );
  }

  Widget _buildViewMode(ThemeData theme, ExamQuestion q, Color typeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question text
          Text(q.question, style: const TextStyle(fontSize: 14, height: 1.45)),
          const SizedBox(height: 10),

          // MCQ options
          if (q.type == 'mcq' && q.options != null) ...[
            ...q.options!.asMap().entries.map((entry) {
              final letter = String.fromCharCode(65 + entry.key); // A B C D
              final opt = entry.value;
              final isCorrect = opt == q.correctAnswer;
              final isSelected = _selectedOption == opt;
              Color? bg;
              Color border = theme.dividerColor;
              if (_showAnswer && isCorrect) {
                bg = Colors.green.withValues(alpha: 0.12);
                border = Colors.green;
              } else if (isSelected && !_showAnswer) {
                bg = theme.colorScheme.primaryContainer.withValues(alpha: 0.5);
                border = theme.colorScheme.primary;
              }
              return GestureDetector(
                onTap: () => setState(() => _selectedOption = opt),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '$letter.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(opt, style: const TextStyle(fontSize: 13)),
                      ),
                      if (_showAnswer && isCorrect)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                          size: 16,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ],

          // True / False
          if (q.type == 'true_false') ...[
            Row(
              children: ['True', 'False'].map((opt) {
                final isCorrect = opt == q.correctAnswer;
                final isSelected = _selectedOption == opt;
                Color? bg;
                Color border = theme.dividerColor;
                if (_showAnswer && isCorrect) {
                  bg = Colors.green.withValues(alpha: 0.12);
                  border = Colors.green;
                } else if (isSelected && !_showAnswer) {
                  bg = theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.5,
                  );
                  border = theme.colorScheme.primary;
                }
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedOption = opt),
                    child: Container(
                      margin: EdgeInsets.only(right: opt == 'True' ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            opt == 'True'
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                            size: 14,
                            color: _showAnswer && isCorrect
                                ? Colors.green
                                : theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            opt,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // Fill blank / Short / Long — just a hint line
          if (q.type == 'fill_blank' ||
              q.type == 'short_answer' ||
              q.type == 'long_answer') ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: Text(
                _showAnswer
                    ? q.correctAnswer
                    : 'Tap "Reveal Answer" to see the answer',
                style: TextStyle(
                  fontSize: 13,
                  color: _showAnswer
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  fontStyle: _showAnswer ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Action row
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => setState(() => _showAnswer = !_showAnswer),
                icon: Icon(
                  _showAnswer
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 14,
                ),
                label: Text(_showAnswer ? 'Hide Answer' : 'Reveal Answer'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              if (_showAnswer &&
                  q.explanation != null &&
                  q.explanation!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      q.explanation!,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditMode(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question
          TextField(
            controller: _qCtrl,
            maxLines: null,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Question',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 10),

          // Options for MCQ
          if (_optCtrls.isNotEmpty) ...[
            Text(
              'Options',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            ..._optCtrls.asMap().entries.map((entry) {
              final letter = String.fromCharCode(65 + entry.key);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: TextField(
                  controller: entry.value,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    prefixText: '$letter.  ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                ),
              );
            }),
            const SizedBox(height: 6),
          ],

          // Correct answer
          TextField(
            controller: _aCtrl,
            maxLines: null,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Correct Answer',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),

          // Explanation
          TextField(
            controller: _eCtrl,
            maxLines: null,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Explanation (optional)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.all(12),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              FilledButton(onPressed: _saveEdit, child: const Text('Save')),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => setState(() => _isEditing = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Edit Message Bubble ───────────────────────────────────────────────────────

class _EditMessageBubble extends StatelessWidget {
  final ExamMessage msg;

  const _EditMessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = msg.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.imagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(msg.imagePath!),
                  height: 120,
                  width: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(msg.content, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ── Context Bar ───────────────────────────────────────────────────────────────

class _ContextBar extends StatelessWidget {
  final String? subjectName;
  final List<String> chapterNames;
  final VoidCallback onClear;
  final VoidCallback onTap;

  const _ContextBar({
    required this.subjectName,
    required this.chapterNames,
    required this.onClear,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContext = subjectName != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasContext
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasContext
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.book_outlined,
              size: 15,
              color: hasContext
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasContext
                    ? (chapterNames.isEmpty
                          ? subjectName!
                          : '${chapterNames.length} chapter${chapterNames.length > 1 ? 's' : ''} from $subjectName')
                    : 'Tap to select chapter context (optional)',
                style: TextStyle(
                  fontSize: 12,
                  color: hasContext
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
            if (hasContext)
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Context Selector Sheet ────────────────────────────────────────────────────

class _ContextSelectorSheet extends StatefulWidget {
  final String? selectedSubjectId;
  final List<String> selectedChapterIds;
  final void Function(
    String? sId,
    String? sName,
    List<String> cIds,
    List<String> cNames,
  )
  onConfirm;

  const _ContextSelectorSheet({
    required this.selectedSubjectId,
    required this.selectedChapterIds,
    required this.onConfirm,
  });

  @override
  State<_ContextSelectorSheet> createState() => _ContextSelectorSheetState();
}

class _ContextSelectorSheetState extends State<_ContextSelectorSheet> {
  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();

  List<Subject> _subjects = [];
  Map<String, List<Chapter>> _chapterMap = {};
  final Set<String> _expanded = {};
  final Set<String> _selectedChapterIds = {};
  String? _selectedSubjectId;
  String? _selectedSubjectName;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selectedChapterIds.addAll(widget.selectedChapterIds);
    _selectedSubjectId = widget.selectedSubjectId;
    _load();
  }

  Future<void> _load() async {
    final subjects = await _subjectRepo.getAll();
    final map = <String, List<Chapter>>{};
    for (final s in subjects) {
      map[s.id] = await _chapterRepo.getBySubject(s.id);
    }
    if (mounted) {
      setState(() {
        _subjects = subjects;
        _chapterMap = map;
      });
    }
  }

  List<Subject> get _filtered {
    if (_search.isEmpty) return _subjects;
    final q = _search.toLowerCase();
    return _subjects.where((s) {
      if (s.name.toLowerCase().contains(q)) return true;
      return (_chapterMap[s.id] ?? []).any(
        (c) => c.title.toLowerCase().contains(q),
      );
    }).toList();
  }

  void _confirm() {
    final names = <String>[];
    for (final s in _subjects) {
      for (final c in (_chapterMap[s.id] ?? [])) {
        if (_selectedChapterIds.contains(c.id)) names.add(c.title);
      }
    }
    Navigator.pop(context);
    widget.onConfirm(
      _selectedSubjectId,
      _selectedSubjectName,
      _selectedChapterIds.toList(),
      names,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Text(
                  'Select Chapters',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const Spacer(),
                FilledButton(onPressed: _confirm, child: const Text('Done')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search subjects or chapters…',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: _filtered.map((s) {
                final chapters = (_chapterMap[s.id] ?? [])
                    .where(
                      (c) =>
                          _search.isEmpty ||
                          c.title.toLowerCase().contains(_search.toLowerCase()),
                    )
                    .toList();
                final allSelected = chapters.every(
                  (c) => _selectedChapterIds.contains(c.id),
                );
                final someSelected =
                    !allSelected &&
                    chapters.any((c) => _selectedChapterIds.contains(c.id));
                return Column(
                  children: [
                    CheckboxListTile(
                      value: allSelected ? true : (someSelected ? null : false),
                      tristate: true,
                      title: Text(
                        s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      secondary: IconButton(
                        icon: Icon(
                          _expanded.contains(s.id)
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onPressed: () => setState(() {
                          _expanded.contains(s.id)
                              ? _expanded.remove(s.id)
                              : _expanded.add(s.id);
                        }),
                      ),
                      onChanged: (_) {
                        setState(() {
                          if (allSelected) {
                            for (final c in chapters) {
                              _selectedChapterIds.remove(c.id);
                            }
                            if (_selectedSubjectId == s.id) {
                              _selectedSubjectId = null;
                              _selectedSubjectName = null;
                            }
                          } else {
                            _selectedSubjectId = s.id;
                            _selectedSubjectName = s.name;
                            for (final c in chapters) {
                              _selectedChapterIds.add(c.id);
                            }
                          }
                        });
                      },
                    ),
                    if (_expanded.contains(s.id))
                      ...chapters.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: CheckboxListTile(
                            value: _selectedChapterIds.contains(c.id),
                            title: Text(
                              c.title,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              c.className,
                              style: const TextStyle(fontSize: 11),
                            ),
                            dense: true,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedChapterIds.add(c.id);
                                  _selectedSubjectId = s.id;
                                  _selectedSubjectName = s.name;
                                } else {
                                  _selectedChapterIds.remove(c.id);
                                }
                              });
                            },
                          ),
                        ),
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exam Config Dialog ────────────────────────────────────────────────────────

class _ExamConfigDialog extends StatefulWidget {
  final _ExamConfig config;
  final String type;

  const _ExamConfigDialog({required this.config, required this.type});

  @override
  State<_ExamConfigDialog> createState() => _ExamConfigDialogState();
}

class _ExamConfigDialogState extends State<_ExamConfigDialog> {
  late int _qCount;
  late int? _timeLimit;
  late String _difficulty;
  late int _mcqOptionCount;

  static const _timeLimits = [null, 5, 10, 15, 20, 30, 45, 60];
  static const _counts = [5, 10, 15, 20, 25, 30];

  @override
  void initState() {
    super.initState();
    _qCount = widget.config.questionCount;
    _timeLimit = widget.config.timeLimit;
    _difficulty = widget.config.difficulty;
    _mcqOptionCount = widget.config.mcqOptionCount;
  }

  @override
  Widget build(BuildContext context) {
    final isMcq = widget.type == 'mcq' || widget.type == 'mixed';

    return AlertDialog(
      title: const Text(
        'Exam Settings',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question count
            _Label('Number of Questions'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: _counts.map((c) {
                final sel = _qCount == c;
                return ChoiceChip(
                  label: Text('$c'),
                  selected: sel,
                  onSelected: (_) => setState(() => _qCount = c),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Time limit
            _Label('Time Limit'),
            const SizedBox(height: 6),
            DropdownButtonFormField<int?>(
              initialValue: _timeLimit,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
              items: _timeLimits
                  .map(
                    (t) => DropdownMenuItem(
                      value: t,
                      child: Text(t == null ? 'No limit' : '$t minutes'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _timeLimit = v),
            ),
            const SizedBox(height: 16),

            // Difficulty
            _Label('Difficulty'),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'easy', label: Text('Easy')),
                ButtonSegment(value: 'medium', label: Text('Medium')),
                ButtonSegment(value: 'hard', label: Text('Hard')),
                ButtonSegment(value: 'mixed', label: Text('Mixed')),
              ],
              selected: {_difficulty},
              onSelectionChanged: (s) => setState(() => _difficulty = s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            const SizedBox(height: 16),

            // MCQ options
            if (isMcq) ...[
              _Label('Options per Question'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                  ButtonSegment(value: 5, label: Text('5')),
                ],
                selected: {_mcqOptionCount},
                onSelectionChanged: (s) =>
                    setState(() => _mcqOptionCount = s.first),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ExamConfig(
              questionCount: _qCount,
              timeLimit: _timeLimit,
              difficulty: _difficulty,
              mcqOptionCount: _mcqOptionCount,
            ),
          ),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    ),
  );
}

// ── Stat Chip ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }
}

// ── Image Preview ─────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _ImagePreview({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(path),
            height: 80,
            width: 80,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const SizedBox.shrink(),
          ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    ),
  );
}

// ── Typing Indicator ──────────────────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.45);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final t = (_ctrl.value - delay).clamp(0.0, 1.0);
            final opacity =
                (0.3 + 0.7 * (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
