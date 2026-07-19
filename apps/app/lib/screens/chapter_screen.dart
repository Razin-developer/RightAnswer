import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../constants/tool_types.dart';
import '../models/app_exception.dart';
import '../models/chapter.dart';
import '../models/chunk.dart';
import '../models/queued_request.dart';
import '../models/subject.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/import_export_service.dart';
import '../services/notification_service.dart';
import '../services/backend_generation_service.dart';
import '../services/queue_service.dart';
import '../services/pdf_import_service.dart';
import '../services/retrieval_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/loading_overlay.dart';
import 'result_screen.dart';

class ChapterScreen extends StatefulWidget {
  final Chapter chapter;
  final Subject subject;

  const ChapterScreen({
    super.key,
    required this.chapter,
    required this.subject,
  });

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen> {
  final _chunkRepo = ChunkRepository();
  final _chapterRepo = ChapterRepository();
  final _settingsRepo = SettingsRepository();
  late final RetrievalService _retrieval;
  late final BackendGenerationService _backendGeneration;

  final _contentCtrl = TextEditingController();
  final _questionCtrl = TextEditingController();
  final _contentFocus = FocusNode();

  late Chapter _chapter;
  List<Chunk> _chunks = [];
  bool _loading = false;
  bool _processingChunks = false;
  bool _extractingImages = false;
  bool _importingPdf = false;
  bool _sharingLink = false;
  bool _editingContent = false;
  String _statusMessage = '';
  List<String> _sourceImagePaths = [];

  @override
  void initState() {
    super.initState();
    _chapter = widget.chapter;
    _retrieval = RetrievalService(_chunkRepo);
    _backendGeneration = BackendGenerationService(
      _settingsRepo,
      UsageLogRepository(),
      _retrieval,
    );
    _contentCtrl.text = _chapter.rawContent;
    _loadChunks();
  }

  @override
  void dispose() {
    _contentCtrl.dispose();
    _questionCtrl.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadChunks() async {
    final chunks = await _chunkRepo.getByChapter(_chapter.id);
    if (mounted) setState(() => _chunks = chunks);
  }

  Future<void> _pickTextbookPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _sourceImagePaths = [..._sourceImagePaths, picked.path];
      });
    } catch (e) {
      if (mounted) {
        AppFeedback.showToast(
          context,
          'Could not open the camera: ${AppException.from(e).message}',
        );
      }
    }
  }

  Future<void> _pickTextbookImages() async {
    try {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _sourceImagePaths = [
          ..._sourceImagePaths,
          ...picked.map((file) => file.path),
        ];
      });
    } catch (e) {
      if (mounted) {
        AppFeedback.showToast(
          context,
          'Could not open photos: ${AppException.from(e).message}',
        );
      }
    }
  }

  void _removeTextbookImage(String path) {
    setState(() {
      _sourceImagePaths = _sourceImagePaths
          .where((item) => item != path)
          .toList();
    });
  }

  Future<void> _extractTextFromImages({bool processAfter = false}) async {
    if (_sourceImagePaths.isEmpty) {
      AppFeedback.showToast(context, 'Add at least one textbook photo first');
      return;
    }
    if (!AppConfig.hasApiUrl) {
      await AppFeedback.showErrorDialog(
        context,
        AppException.configuration(
          'Build is missing the backend API URL. Add API_URL when building the app.',
        ),
      );
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(
        context,
        'Connect to the internet to extract text from images',
      );
      return;
    }

    setState(() {
      _extractingImages = true;
      _statusMessage = 'Reading textbook images...';
    });

    try {
      final extracted = await _backendGeneration.extractChapterTextFromImages(
        imagePaths: _sourceImagePaths,
        chapterTitle: _chapter.title,
        subjectName: widget.subject.name,
      );
      final existing = _contentCtrl.text.trim();
      final merged = existing.isEmpty
          ? extracted.combinedText
          : '$existing\n\n${extracted.combinedText}';

      _contentCtrl.text = merged;
      setState(() {
        _editingContent = true;
        _statusMessage = extracted.failedFiles.isEmpty
            ? 'Imported ${extracted.processedCount} textbook page(s)'
            : 'Imported ${extracted.processedCount} page(s), skipped ${extracted.failedFiles.length}';
      });

      if (mounted) {
        AppFeedback.showToast(
          context,
          extracted.failedFiles.isEmpty
              ? 'Text imported into the chapter editor'
              : 'Imported with some skipped images',
        );
      }

      if (processAfter) {
        await _saveAndProcess();
      }
    } catch (e) {
      if (mounted) await AppFeedback.showErrorDialog(context, e);
    } finally {
      if (mounted) {
        setState(() => _extractingImages = false);
      }
    }
  }

  Future<void> _importFromPdf() async {
    final path = await PdfImportService.instance.pickPdfPath();
    if (path == null || !mounted) return;

    setState(() {
      _importingPdf = true;
      _statusMessage = 'Opening PDF…';
    });

    try {
      final result = await PdfImportService.instance.extractText(
        path,
        onStatus: (s) {
          if (mounted) setState(() => _statusMessage = s);
        },
      );

      if (!mounted) return;

      final existing = _contentCtrl.text.trim();
      _contentCtrl.text = existing.isEmpty
          ? result.text
          : '$existing\n\n${result.text}';

      setState(() {
        _editingContent = true;
        _statusMessage = result.truncated
            ? 'Imported first 60 pages of ${result.pageCount}-page PDF via OCR'
            : 'Imported ${result.pageCount} PDF page(s) via OCR';
      });
      AppFeedback.showToast(context, 'PDF content added to editor');
    } catch (e) {
      if (mounted) await AppFeedback.showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _importingPdf = false);
    }
  }

  // ── Share / Import via Link ───────────────────────────────────────────────

  Future<void> _shareViaLink() async {
    if (!AuthService.instance.isLoggedIn) {
      AppFeedback.showToast(context, 'Sign in to share chapters');
      return;
    }
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(context, 'You are offline');
      return;
    }
    setState(() => _sharingLink = true);
    try {
      final bytes = await ImportExportService.instance.exportChapterToBytes(
        _chapter.id,
        widget.subject.id,
      );
      final result = await CloudSyncService.instance.uploadContentZip(
        bytes: bytes,
        metadata: {'type': 'chapter', 'name': _chapter.title},
      );
      final url = result['url'] as String? ?? '';
      if (mounted) _showLinkDialog(url);
    } catch (e) {
      if (mounted) AppFeedback.showToast(context, 'Failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _sharingLink = false);
    }
  }

  void _showLinkDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Chapter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this link to let others import this chapter.\nExpires in 10 minutes.',
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

  void _importFromLink() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import from Link'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste share link',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.pop(ctx);
              await _doImportFromLink(raw);
            },
            child: const Text('Import'),
          ),
        ],
      ),
    );
  }

  Future<void> _doImportFromLink(String urlOrToken) async {
    setState(() {
      _loading = true;
      _statusMessage = 'Downloading…';
    });
    try {
      final bytes = await CloudSyncService.instance.downloadContentZip(
        urlOrToken,
      );
      if (!mounted) return;
      setState(() => _statusMessage = 'Importing…');
      final result = await ImportExportService.instance.importFromBytes(bytes);
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        'Imported ${result.chapters} chapter(s)',
      );
    } catch (e) {
      if (mounted) {
        AppFeedback.showToast(context, 'Import failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ── Content CRUD ─────────────────────────────────────────────────────────

  void _startEditing() {
    setState(() => _editingContent = true);
    _contentFocus.requestFocus();
  }

  Future<void> _saveAndProcess() async {
    final text = _contentCtrl.text.trim();
    if (text.isEmpty) {
      AppFeedback.showToast(context, 'Content cannot be empty');
      return;
    }
    if (text.length < 20) {
      AppFeedback.showToast(context, 'Content is too short to process');
      return;
    }

    setState(() {
      _processingChunks = true;
      _editingContent = false;
      _statusMessage = 'Splitting into chunks…';
    });

    try {
      // Replace old chunks with new ones
      await _chunkRepo.deleteByChapter(_chapter.id);
      final chunks = await _retrieval.processAndStoreChunks(_chapter.id, text);

      // Persist raw content for future editing
      await _chapterRepo.updateRawContent(_chapter.id, text);
      setState(() {
        _chapter = _chapter.copyWith(rawContent: text);
        _chunks = chunks;
        _statusMessage = '${chunks.length} chunks ready';
      });

      if (!AppConfig.hasApiUrl) {
        setState(
          () => _statusMessage =
              '${chunks.length} chunks ready - add API_URL to enable embeddings',
        );
        return;
      }

      setState(() => _statusMessage = 'Creating embeddings…');
      try {
        final embeddings = await _backendGeneration.generateEmbeddings(
          chunks.map((c) => c.text).toList(),
        );
        for (int i = 0; i < chunks.length; i++) {
          await _chunkRepo.updateEmbedding(
            chunks[i].id,
            jsonEncode(embeddings[i]),
          );
        }
        setState(
          () => _statusMessage = '${chunks.length} chunks + embeddings ready',
        );
      } catch (e) {
        setState(
          () => _statusMessage =
              '${chunks.length} chunks ready (embeddings skipped: ${AppException.from(e).message})',
        );
      }
    } catch (e) {
      setState(() => _statusMessage = AppException.from(e).message);
      if (mounted) await AppFeedback.showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _processingChunks = false);
    }
  }

  Future<void> _clearContent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Content'),
        content: const Text(
          'This removes all processed chunks and clears the content field. The chapter itself is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _chunkRepo.deleteByChapter(_chapter.id);
    await _chapterRepo.updateRawContent(_chapter.id, '');
    if (mounted) {
      setState(() {
        _chapter = _chapter.copyWith(rawContent: '');
        _chunks = [];
        _statusMessage = '';
        _contentCtrl.clear();
        _editingContent = false;
      });
    }
  }

  void _cancelEdit() {
    setState(() {
      _contentCtrl.text = _chapter.rawContent;
      _editingContent = false;
    });
    _contentFocus.unfocus();
  }

  // ── Generate ──────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    if (_chunks.isEmpty) {
      AppFeedback.showToast(context, 'Process the chapter content first');
      return;
    }
    if (!AppConfig.hasApiUrl) {
      await AppFeedback.showErrorDialog(
        context,
        AppException.configuration(
          'Build is missing the backend API URL. Add API_URL when building the app.',
        ),
      );
      return;
    }

    final question = _questionCtrl.text.trim();
    // Auto-select tool: if there's a question, explain it; otherwise summarise
    final toolType = question.isEmpty
        ? ToolType.chapterSummary
        : ToolType.explainSimple;

    if (!ConnectivityService.instance.isOnline) {
      final gradeLevel =
          await _settingsRepo.get(SettingKeys.defaultGradeLevel) ?? 'Grade 10';
      final tone = await _settingsRepo.get(SettingKeys.defaultTone) ?? 'normal';
      final outputLength =
          await _settingsRepo.get(SettingKeys.defaultOutputLength) ?? 'medium';
      final language =
          await _settingsRepo.get(SettingKeys.defaultLanguage) ?? 'English';

      await QueueService.instance.enqueue(
        QueuedRequest(
          id: const Uuid().v4(),
          chapterId: _chapter.id,
          subjectId: widget.subject.id,
          toolType: toolType,
          question: question.isEmpty ? null : question,
          language: language,
          gradeLevel: gradeLevel,
          tone: tone,
          outputLength: outputLength,
          status: 'pending',
          createdAt: DateTime.now(),
        ),
      );

      await NotificationService.instance.showOfflineQueued(toolType);
      if (mounted) {
        AppFeedback.showToast(
          context,
          'Queued — will generate when you\'re back online',
        );
      }
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = 'Retrieving context…';
    });

    try {
      final relevantChunks = await _retrieval.searchChapter(
        _chapter.id,
        question,
      );
      setState(() => _statusMessage = 'Generating…');

      final gradeLevel =
          await _settingsRepo.get(SettingKeys.defaultGradeLevel) ?? 'Grade 10';
      final tone = await _settingsRepo.get(SettingKeys.defaultTone) ?? 'normal';
      final outputLength =
          await _settingsRepo.get(SettingKeys.defaultOutputLength) ?? 'medium';
      final language =
          await _settingsRepo.get(SettingKeys.defaultLanguage) ?? 'English';

      final result = await _backendGeneration.generateFromContext(
        toolType: toolType,
        question: question.isEmpty ? null : question,
        contextChunks: relevantChunks.map((c) => c.text).toList(),
        language: language,
        gradeLevel: gradeLevel,
        tone: tone,
        outputLength: outputLength,
      );

      final notifyEnabled =
          await _settingsRepo.get(SettingKeys.notifyOnComplete) ?? 'true';
      if (notifyEnabled == 'true') {
        await NotificationService.instance.showGenerationComplete(
          toolType: toolType,
          chapterTitle: _chapter.title,
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
            chapterId: _chapter.id,
            subjectId: widget.subject.id,
            language: language,
          ),
        ),
      );
    } catch (e) {
      if (mounted) await AppFeedback.showErrorDialog(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ── Study Aids (one-tap) ─────────────────────────────────────────────────

  Future<void> _generateStudyAid(String toolType) async {
    if (_chunks.isEmpty) {
      AppFeedback.showToast(context, 'Process the chapter content first');
      return;
    }
    if (!AppConfig.hasApiUrl) {
      await AppFeedback.showErrorDialog(
        context,
        AppException.configuration(
          'Build is missing the backend API URL. Add API_URL when building the app.',
        ),
      );
      return;
    }

    if (!ConnectivityService.instance.isOnline) {
      final gradeLevel =
          await _settingsRepo.get(SettingKeys.defaultGradeLevel) ?? 'Grade 10';
      final tone = await _settingsRepo.get(SettingKeys.defaultTone) ?? 'normal';
      final outputLength =
          await _settingsRepo.get(SettingKeys.defaultOutputLength) ?? 'medium';
      final language =
          await _settingsRepo.get(SettingKeys.defaultLanguage) ?? 'English';

      await QueueService.instance.enqueue(
        QueuedRequest(
          id: const Uuid().v4(),
          chapterId: _chapter.id,
          subjectId: widget.subject.id,
          toolType: toolType,
          question: null,
          language: language,
          gradeLevel: gradeLevel,
          tone: tone,
          outputLength: outputLength,
          status: 'pending',
          createdAt: DateTime.now(),
        ),
      );
      await NotificationService.instance.showOfflineQueued(toolType);
      if (mounted) {
        AppFeedback.showToast(
          context,
          'Queued — will generate when back online',
        );
      }
      return;
    }

    setState(() {
      _loading = true;
      _statusMessage = 'Generating ${ToolType.displayName(toolType)}…';
    });

    try {
      final relevantChunks = await _retrieval.searchChapter(
        _chapter.id,
        'overview',
      );
      final gradeLevel =
          await _settingsRepo.get(SettingKeys.defaultGradeLevel) ?? 'Grade 10';
      final tone = await _settingsRepo.get(SettingKeys.defaultTone) ?? 'normal';
      final outputLength =
          await _settingsRepo.get(SettingKeys.defaultOutputLength) ?? 'long';
      final language =
          await _settingsRepo.get(SettingKeys.defaultLanguage) ?? 'English';

      final result = await _backendGeneration.generateFromContext(
        toolType: toolType,
        question: null,
        contextChunks: relevantChunks.map((c) => c.text).toList(),
        language: language,
        gradeLevel: gradeLevel,
        tone: tone,
        outputLength: outputLength,
      );

      final notifyEnabled =
          await _settingsRepo.get(SettingKeys.notifyOnComplete) ?? 'true';
      if (notifyEnabled == 'true') {
        await NotificationService.instance.showGenerationComplete(
          toolType: toolType,
          chapterTitle: _chapter.title,
        );
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            result: result,
            toolType: toolType,
            question: null,
            usedChunks: relevantChunks,
            chapterId: _chapter.id,
            subjectId: widget.subject.id,
            language: language,
          ),
        ),
      );
    } catch (e) {
      if (mounted) await AppFeedback.showErrorDialog(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _statusMessage = '';
        });
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasContent = _contentCtrl.text.trim().isNotEmpty;
    final hasChunks = _chunks.isNotEmpty;

    return LoadingOverlay(
      isLoading: _loading,
      message: _statusMessage.isEmpty ? 'Generating…' : _statusMessage,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _chapter.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _chapter.className,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'share_link') _shareViaLink();
                if (v == 'import_link') _importFromLink();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'share_link',
                  child: Row(
                    children: [
                      Icon(Icons.ios_share_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Share via Link'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'import_link',
                  child: Row(
                    children: [
                      Icon(Icons.link, size: 18),
                      SizedBox(width: 10),
                      Text('Import from Link'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: hasChunks
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(26),
                  child: Container(
                    width: double.infinity,
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.45,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 13,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_chunks.length} chunks processed — ready to generate',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        ),
        body: GestureDetector(
          onTap: () {
            if (_editingContent) {
              // keep focus
            } else {
              FocusScope.of(context).unfocus();
            }
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Content section ─────────────────────────────────────
                _SectionHeader(
                  icon: Icons.article_outlined,
                  label: 'Chapter Content',
                  trailing: _editingContent
                      ? null
                      : hasContent
                      ? TextButton.icon(
                          onPressed: _startEditing,
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 10),

                // Content textarea
                TextField(
                  controller: _contentCtrl,
                  focusNode: _contentFocus,
                  maxLines: _editingContent ? null : 8,
                  minLines: _editingContent ? 8 : 1,
                  readOnly: !_editingContent && hasContent,
                  onChanged: (_) => setState(() {}),
                  onTap: () {
                    if (!_editingContent && !hasContent) _startEditing();
                  },
                  decoration: InputDecoration(
                    hintText: 'Paste or type the chapter content here…',
                    alignLabelWithHint: true,
                    filled: !_editingContent && hasContent,
                    fillColor: theme.colorScheme.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: theme.dividerColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.all(14),
                    suffixIcon: _editingContent && _contentCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _contentCtrl.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Import Textbook Pages',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Import textbook pages via camera, gallery photos, or a PDF file. Text is extracted and added to the editor.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _extractingImages
                                ? null
                                : _pickTextbookPhoto,
                            icon: const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                            ),
                            label: const Text('Camera'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _extractingImages
                                ? null
                                : _pickTextbookImages,
                            icon: const Icon(
                              Icons.photo_library_outlined,
                              size: 16,
                            ),
                            label: const Text('Photos'),
                          ),
                          OutlinedButton.icon(
                            onPressed: (_extractingImages || _importingPdf)
                                ? null
                                : _importFromPdf,
                            icon: _importingPdf
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.picture_as_pdf_outlined,
                                    size: 16,
                                  ),
                            label: Text(_importingPdf ? 'Scanning…' : 'PDF'),
                          ),
                          FilledButton.icon(
                            onPressed: _extractingImages
                                ? null
                                : () => _extractTextFromImages(),
                            icon: _extractingImages
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                  ),
                            label: Text(
                              _extractingImages
                                  ? 'Extracting...'
                                  : 'Extract Text',
                            ),
                          ),
                        ],
                      ),
                      if (_sourceImagePaths.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 82,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _sourceImagePaths.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final path = _sourceImagePaths[index];
                              return Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _ImageFullscreenPage(
                                          imagePath: path,
                                          caption:
                                              'Image ${index + 1} of ${_sourceImagePaths.length}',
                                          onRemove: _extractingImages
                                              ? null
                                              : () =>
                                                    _removeTextbookImage(path),
                                        ),
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.file(
                                        File(path),
                                        width: 82,
                                        height: 82,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: _extractingImages
                                          ? null
                                          : () => _removeTextbookImage(path),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            onPressed: _extractingImages
                                ? null
                                : () => _extractTextFromImages(
                                    processAfter: true,
                                  ),
                            icon: const Icon(
                              Icons.library_add_check_rounded,
                              size: 16,
                            ),
                            label: const Text('Extract, Combine, and Process'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Character count when editing
                if (_editingContent && hasContent)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${_contentCtrl.text.trim().length} characters',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Action buttons for content
                if (_editingContent)
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _processingChunks ? null : _saveAndProcess,
                        icon: _processingChunks
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(
                          _processingChunks ? 'Processing…' : 'Process & Save',
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _processingChunks ? null : _cancelEdit,
                        child: const Text('Cancel'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      if (!hasContent)
                        FilledButton.icon(
                          onPressed: _processingChunks ? null : _startEditing,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('Add Content'),
                        ),
                      if (hasContent && !hasChunks)
                        FilledButton.icon(
                          onPressed: _processingChunks ? null : _saveAndProcess,
                          icon: _processingChunks
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow_rounded, size: 18),
                          label: Text(
                            _processingChunks
                                ? 'Processing…'
                                : 'Process Content',
                          ),
                        ),
                      if (hasChunks) ...[
                        OutlinedButton.icon(
                          onPressed: _processingChunks ? null : _saveAndProcess,
                          icon: _processingChunks
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.primary,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 16),
                          label: Text(
                            _processingChunks ? 'Reprocessing…' : 'Reprocess',
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _processingChunks ? null : _clearContent,
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('Clear'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(
                              color: Colors.red.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                // Status row
                if (_statusMessage.isNotEmpty && !_loading) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 13,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.45,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 32),
                Divider(color: theme.dividerColor),
                const SizedBox(height: 28),

                // ── Generate section ──────────────────────────────────
                _SectionHeader(
                  icon: Icons.auto_awesome_outlined,
                  label: 'Generate',
                ),
                const SizedBox(height: 10),

                if (!hasChunks)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.35,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Add and process chapter content first',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  TextField(
                    controller: _questionCtrl,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText:
                          'Ask a question, or leave blank for a chapter summary…',
                      prefixIcon: Icon(
                        Icons.help_outline_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: theme.colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      suffixIcon: _questionCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _questionCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _questionCtrl.text.trim().isEmpty
                        ? 'No question → generates a chapter summary'
                        : 'Question → generates an explanation',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _generate,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                        _questionCtrl.text.trim().isEmpty
                            ? 'Generate Summary'
                            : 'Generate Answer',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],

                // ── Study Aids ────────────────────────────────────────
                const SizedBox(height: 32),
                Divider(color: theme.dividerColor),
                const SizedBox(height: 28),

                _SectionHeader(
                  icon: Icons.auto_stories_outlined,
                  label: 'Study Aids',
                  trailing: hasChunks
                      ? null
                      : Text(
                          'Process content first',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.38,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.4,
                  children: [
                    _StudyAidButton(
                      icon: Icons.style_outlined,
                      label: 'Flashcards',
                      color: Colors.orange,
                      enabled: hasChunks,
                      onTap: () => _generateStudyAid(ToolType.flashcards),
                    ),
                    _StudyAidButton(
                      icon: Icons.notes_rounded,
                      label: 'Revision Notes',
                      color: Colors.teal,
                      enabled: hasChunks,
                      onTap: () => _generateStudyAid(ToolType.revisionNotes),
                    ),
                    _StudyAidButton(
                      icon: Icons.functions_rounded,
                      label: 'Key Formulas',
                      color: Colors.indigo,
                      enabled: hasChunks,
                      onTap: () =>
                          _generateStudyAid(ToolType.importantFormulas),
                    ),
                    _StudyAidButton(
                      icon: Icons.abc_rounded,
                      label: 'Definitions',
                      color: Colors.purple,
                      enabled: hasChunks,
                      onTap: () =>
                          _generateStudyAid(ToolType.importantDefinitions),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Image Fullscreen ─────────────────────────────────────────────────────────

class _ImageFullscreenPage extends StatelessWidget {
  final String imagePath;
  final String caption;
  final VoidCallback? onRemove;

  const _ImageFullscreenPage({
    required this.imagePath,
    required this.caption,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(caption, style: const TextStyle(fontSize: 14)),
        actions: [
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Remove',
              onPressed: () {
                Navigator.pop(context);
                onRemove!();
              },
            ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(File(imagePath), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ── Shared ─────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;

  const _SectionHeader({
    required this.icon,
    required this.label,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
            letterSpacing: 0.5,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

// ── Study Aid Button ──────────────────────────────────────────────────────────

class _StudyAidButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _StudyAidButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = enabled
        ? color
        : theme.colorScheme.onSurface.withValues(alpha: 0.25);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.09)
              : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? color.withValues(alpha: 0.35) : theme.dividerColor,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: effectiveColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
