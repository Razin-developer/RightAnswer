import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../constants/tool_types.dart';
import '../models/chapter.dart';
import '../models/chunk.dart';
import '../models/queued_request.dart';
import '../models/subject.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';
import '../services/openai_service.dart';
import '../services/queue_service.dart';
import '../services/retrieval_service.dart';
import '../widgets/loading_overlay.dart';
import 'queue_screen.dart';
import 'result_screen.dart';

class ChapterScreen extends StatefulWidget {
  final Chapter chapter;
  final Subject subject;

  const ChapterScreen({super.key, required this.chapter, required this.subject});

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen> {
  final _chunkRepo = ChunkRepository();
  final _settingsRepo = SettingsRepository();
  late final RetrievalService _retrieval;
  late final OpenAIService _openAI;

  final _textCtrl = TextEditingController();
  final _questionCtrl = TextEditingController();

  List<Chunk> _chunks = [];
  bool _loading = false;
  bool _processingChunks = false;
  String _statusMessage = '';

  String _selectedLanguage = 'English';
  static const List<String> _languages = [
    'English', 'Hindi', 'Urdu', 'Arabic', 'French', 'Spanish',
    'German', 'Mandarin', 'Bengali', 'Portuguese', 'Turkish',
  ];

  @override
  void initState() {
    super.initState();
    _retrieval = RetrievalService(_chunkRepo);
    _openAI = OpenAIService(_settingsRepo, UsageLogRepository(), _retrieval);
    _loadChunks();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final lang = await _settingsRepo.get(SettingKeys.defaultLanguage);
    if (lang != null && mounted) setState(() => _selectedLanguage = lang);
  }

  Future<void> _loadChunks() async {
    final chunks = await _chunkRepo.getByChapter(widget.chapter.id);
    if (mounted) setState(() => _chunks = chunks);
  }

  Future<void> _processText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _snack('Please paste chapter text first');
      return;
    }
    setState(() { _processingChunks = true; _statusMessage = 'Splitting into chunks…'; });
    try {
      final chunks = await _retrieval.processAndStoreChunks(widget.chapter.id, text);
      setState(() { _chunks = chunks; _statusMessage = '${chunks.length} chunks created'; });

      final apiKey = await _settingsRepo.get(SettingKeys.openAiApiKey);
      if (apiKey != null && apiKey.isNotEmpty) {
        setState(() => _statusMessage = 'Creating embeddings…');
        try {
          final embeddings = await _openAI.generateEmbeddings(chunks.map((c) => c.text).toList());
          for (int i = 0; i < chunks.length; i++) {
            await _chunkRepo.updateEmbedding(chunks[i].id, jsonEncode(embeddings[i]));
          }
          setState(() => _statusMessage = '${chunks.length} chunks + embeddings ready');
        } catch (_) {
          setState(() => _statusMessage = '${chunks.length} chunks ready (embeddings skipped)');
        }
      } else {
        setState(() => _statusMessage = '${chunks.length} chunks ready');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _processingChunks = false);
    }
  }

  Future<void> _generate(String toolType) async {
    if (_chunks.isEmpty) {
      _snack('Process chapter text first');
      return;
    }
    final apiKey = await _settingsRepo.get(SettingKeys.openAiApiKey);
    if (apiKey == null || apiKey.trim().isEmpty) {
      _snack('Add your OpenAI API key in Settings');
      return;
    }
    final question = _questionCtrl.text.trim();
    if (toolType == ToolType.explainSimple && question.isEmpty) {
      _snack('Enter a topic or question to explain');
      return;
    }

    // ── Offline path: queue the request ─────────────────────────────────────
    if (!ConnectivityService.instance.isOnline) {
      final gradeLevel = await _settingsRepo.get(SettingKeys.defaultGradeLevel) ?? 'Grade 10';
      final tone = await _settingsRepo.get(SettingKeys.defaultTone) ?? 'normal';
      final outputLength = await _settingsRepo.get(SettingKeys.defaultOutputLength) ?? 'medium';

      await QueueService.instance.enqueue(QueuedRequest(
        id: const Uuid().v4(),
        chapterId: widget.chapter.id,
        subjectId: widget.subject.id,
        toolType: toolType,
        question: question.isEmpty ? null : question,
        language: _selectedLanguage,
        gradeLevel: gradeLevel,
        tone: tone,
        outputLength: outputLength,
        status: 'pending',
        createdAt: DateTime.now(),
      ));

      await NotificationService.instance.showOfflineQueued(toolType);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ToolType.displayName(toolType)} queued — will generate when online'),
          action: SnackBarAction(
            label: 'View Queue',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QueueScreen())),
          ),
        ),
      );
      return;
    }

    setState(() { _loading = true; _statusMessage = 'Retrieving context…'; });
    try {
      final relevantChunks = await _retrieval.searchChapter(widget.chapter.id, question);
      setState(() => _statusMessage = 'Generating with AI…');

      final gradeLevel = await _settingsRepo.get(SettingKeys.defaultGradeLevel) ?? 'Grade 10';
      final tone = await _settingsRepo.get(SettingKeys.defaultTone) ?? 'normal';
      final outputLength = await _settingsRepo.get(SettingKeys.defaultOutputLength) ?? 'medium';

      final result = await _openAI.generateFromContext(
        toolType: toolType,
        question: question.isEmpty ? null : question,
        contextChunks: relevantChunks.map((c) => c.text).toList(),
        language: _selectedLanguage,
        gradeLevel: gradeLevel,
        tone: tone,
        outputLength: outputLength,
      );

      // Notify (fires even if the user has navigated away from this screen)
      final notifyEnabled =
          await _settingsRepo.get(SettingKeys.notifyOnComplete) ?? 'true';
      if (notifyEnabled == 'true') {
        await NotificationService.instance.showGenerationComplete(
          toolType: toolType,
          chapterTitle: widget.chapter.title,
        );
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            result: result,
            toolType: toolType,
            question: question.isEmpty ? null : question,
            usedChunks: relevantChunks,
            chapterId: widget.chapter.id,
            subjectId: widget.subject.id,
            language: _selectedLanguage,
          ),
        ),
      );
    } on Exception catch (e) {
      if (mounted) _snack('Error: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() { _loading = false; _statusMessage = ''; });
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChunks = _chunks.isNotEmpty;

    return LoadingOverlay(
      isLoading: _loading,
      message: _statusMessage.isEmpty ? 'Generating…' : _statusMessage,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.chapter.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(widget.chapter.className,
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w400)),
            ],
          ),
          bottom: hasChunks
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(28),
                  child: Container(
                    width: double.infinity,
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    child: Text(
                      '${_chunks.length} chunks processed  •  Ready to generate',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                    ),
                  ),
                )
              : null,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Text input section ────────────────────────────────────
              _label('Chapter Text', theme),
              const SizedBox(height: 8),
              TextField(
                controller: _textCtrl,
                maxLines: 7,
                decoration: InputDecoration(
                  hintText: 'Paste your chapter content here…',
                  alignLabelWithHint: true,
                  suffixIcon: _textCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () { _textCtrl.clear(); setState(() {}); },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _processingChunks ? null : _processText,
                    icon: _processingChunks
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(_processingChunks ? 'Processing…' : 'Process Text'),
                  ),
                  if (hasChunks) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _chunkRepo.deleteByChapter(widget.chapter.id);
                        _textCtrl.clear();
                        if (mounted) setState(() { _chunks = []; _statusMessage = ''; });
                      },
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ],
              ),
              if (_statusMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 14,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_statusMessage,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 28),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 20),

              // ── Study tools section ───────────────────────────────────
              _label('Study Tools', theme),
              const SizedBox(height: 14),

              // Language + Question in a card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.language, size: 16,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        const SizedBox(width: 8),
                        const Text('Language', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _selectedLanguage,
                            isDense: true,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              isDense: true,
                            ),
                            items: _languages
                                .map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 13))))
                                .toList(),
                            onChanged: (v) { if (v != null) setState(() => _selectedLanguage = v); },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _questionCtrl,
                      decoration: InputDecoration(
                        labelText: 'Topic / Question (for Explain)',
                        hintText: 'e.g. What is Newton\'s First Law?',
                        prefixIcon: Icon(Icons.help_outline, size: 18,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              ..._toolGroups(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, ThemeData theme) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
          letterSpacing: 0.5,
        ),
      );

  List<Widget> _toolGroups(ThemeData theme) {
    final groups = [
      {
        'title': 'UNDERSTANDING',
        'icon': Icons.lightbulb_outline,
        'tools': [ToolType.explainSimple, ToolType.chapterSummary, ToolType.keyPoints, ToolType.learningObjectives],
      },
      {
        'title': 'PRACTICE QUESTIONS',
        'icon': Icons.quiz_outlined,
        'tools': [ToolType.quiz, ToolType.mcq, ToolType.trueFalse, ToolType.fillBlanks, ToolType.shortAnswer, ToolType.longAnswer],
      },
      {
        'title': 'STUDY AIDS',
        'icon': Icons.style_outlined,
        'tools': [ToolType.flashcards, ToolType.revisionNotes, ToolType.importantFormulas, ToolType.importantDefinitions],
      },
    ];

    return groups.map((g) {
      final tools = g['tools'] as List<String>;
      final icon = g['icon'] as IconData;
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                const SizedBox(width: 6),
                Text(g['title'] as String,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        letterSpacing: 0.8)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tools.map((t) => _toolButton(t, theme)).toList(),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _toolButton(String toolType, ThemeData theme) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _generate(toolType),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(10),
          color: theme.colorScheme.surfaceContainer,
        ),
        child: Text(ToolType.displayName(toolType),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurface)),
      ),
    );
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _questionCtrl.dispose();
    super.dispose();
  }
}
