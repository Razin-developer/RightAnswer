import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/subject.dart';
import '../models/chapter.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/chunk_repository.dart';
import '../services/pdf_import_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/loading_overlay.dart';
import 'chapter_screen.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  final _repo = ChapterRepository();
  final _chunkRepo = ChunkRepository();

  List<Chapter> _chapters = [];
  Map<String, int> _chunkCounts = {};
  bool _loading = true;
  bool _importingPdf = false;
  String _importStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final chapters = await _repo.getBySubject(widget.subject.id);
    final chunkCounts = await _chunkRepo.countsByChapters(
      chapters.map((c) => c.id).toList(),
    );
    if (mounted) {
      setState(() {
        _chapters = chapters;
        _chunkCounts = chunkCounts;
        _loading = false;
      });
    }
  }

  Future<void> _importFromPdf() async {
    final path = await PdfImportService.instance.pickPdfPath();
    if (path == null || !mounted) return;

    setState(() {
      _importingPdf = true;
      _importStatus = 'Opening PDF…';
    });

    try {
      final result = await PdfImportService.instance.extractText(
        path,
        onStatus: (s) {
          if (mounted) setState(() => _importStatus = s);
        },
        maxPages: 150,
      );

      if (!mounted) return;

      setState(() => _importStatus = 'Detecting chapters…');
      final detected = PdfImportService.instance.detectChapters(result.text);

      if (!mounted) return;

      // Show confirmation / chapter-naming dialog
      final toCreate = await _showImportDialog(
        detected: detected,
        pageCount: result.pageCount,
        fullText: result.text,
        truncated: result.truncated,
      );
      if (toCreate == null || !mounted) return;

      setState(() => _importStatus = 'Creating chapters…');
      const uuid = Uuid();
      for (int i = 0; i < toCreate.length; i++) {
        setState(() =>
            _importStatus = 'Creating chapter ${i + 1} of ${toCreate.length}…');
        final ch = toCreate[i];
        await _repo.insert(
          Chapter(
            id: uuid.v4(),
            subjectId: widget.subject.id,
            title: ch.title,
            className: 'General',
            rawContent: ch.content,
            createdAt: DateTime.now(),
          ),
        );
      }

      AppFeedback.showSuccessToast(
        context,
        'Created ${toCreate.length} chapter(s) — open each to process content',
      );
      _load();
    } catch (e) {
      if (mounted) await AppFeedback.showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() { _importingPdf = false; _importStatus = ''; });
    }
  }

  Future<List<PdfChapter>?> _showImportDialog({
    required List<PdfChapter> detected,
    required int pageCount,
    required String fullText,
    required bool truncated,
  }) async {
    if (detected.isEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No Chapter Structure Found'),
          content: Text(
            'We scanned $pageCount page(s) but couldn\'t find chapter headings.\n\n'
            '${truncated ? 'Note: only the first 150 pages were scanned.\n\n' : ''}'
            'Create a single chapter with all the extracted text?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create Chapter'),
            ),
          ],
        ),
      );
      if (ok != true) return null;
      return [PdfChapter(title: 'Chapter 1', content: fullText)];
    }

    return showDialog<List<PdfChapter>>(
      context: context,
      builder: (ctx) => _ImportChaptersDialog(
        chapters: detected,
        pageCount: pageCount,
        truncated: truncated,
      ),
    );
  }

  Future<void> _addChapter() async {
    final titleCtrl = TextEditingController();
    final classCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Chapter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Chapter title *',
                hintText: 'e.g. Chapter 3: Motion',
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: classCtrl,
              decoration: const InputDecoration(
                labelText: 'Class / Grade',
                hintText: 'e.g. Grade 10',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (result != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chapter title cannot be empty')));
      return;
    }
    await _repo.insert(Chapter(
      id: Uuid().v4(),
      subjectId: widget.subject.id,
      title: title,
      className: classCtrl.text.trim().isEmpty ? 'General' : classCtrl.text.trim(),
      createdAt: DateTime.now(),
    ));
    _load();
  }

  Future<void> _deleteChapter(Chapter c) async {
    final ok = await _confirmDelete(context, c.title);
    if (!ok) return;
    await _repo.delete(c.id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final readyCount = _chunkCounts.values.where((v) => v > 0).length;

    return LoadingOverlay(
      isLoading: _importingPdf,
      message: _importStatus.isEmpty ? 'Importing PDF…' : _importStatus,
      child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subject.name, style: const TextStyle(fontSize: 16)),
            if (!_loading && _chapters.isNotEmpty)
              Text(
                '$readyCount of ${_chapters.length} chapter${_chapters.length != 1 ? 's' : ''} AI-ready',
                style: TextStyle(
                  fontSize: 11,
                  color: readyCount > 0
                      ? const Color(0xFF059669)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ),
          ],
        ),
        centerTitle: false,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'import_pdf') _importFromPdf();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'import_pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('Import from PDF'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.dividerColor),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isEmpty
              ? _emptyState(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _chapters.length,
                    itemBuilder: (ctx, i) =>
                        _chapterCard(_chapters[i], i, theme),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addChapter,
        icon: const Icon(Icons.add),
        label: const Text('Add Chapter'),
      ),
    ),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.menu_book_outlined, size: 40, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text('No chapters yet',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Add a chapter and upload content to start getting AI answers',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55))),
            const SizedBox(height: 28),
            FilledButton.icon(
                onPressed: _addChapter,
                icon: const Icon(Icons.add),
                label: const Text('Add Chapter')),
          ],
        ),
      );

  Widget _chapterCard(Chapter c, int i, ThemeData theme) {
    final chunkCount = _chunkCounts[c.id] ?? 0;
    final isReady = chunkCount > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChapterScreen(chapter: c, subject: widget.subject)),
          ).then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isReady
                        ? const Color(0xFF059669).withValues(alpha: 0.1)
                        : theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: isReady
                        ? const Icon(Icons.check_rounded,
                            size: 20, color: Color(0xFF059669))
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                                fontSize: 15),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            c.className,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                          ),
                          if (isReady) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$chunkCount chunks',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(width: 8),
                            Text(
                              'No content',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                  onSelected: (v) { if (v == 'delete') _deleteChapter(c); },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Import Chapters Dialog ────────────────────────────────────────────────────

class _ImportChaptersDialog extends StatefulWidget {
  final List<PdfChapter> chapters;
  final int pageCount;
  final bool truncated;

  const _ImportChaptersDialog({
    required this.chapters,
    required this.pageCount,
    required this.truncated,
  });

  @override
  State<_ImportChaptersDialog> createState() => _ImportChaptersDialogState();
}

class _ImportChaptersDialogState extends State<_ImportChaptersDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.chapters
        .map((ch) => TextEditingController(text: ch.title))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.chapters.length} Chapters Detected'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scanned ${widget.pageCount} page(s).'
              '${widget.truncated ? ' (first 150 pages)' : ''}'
              ' Review and rename chapters below.',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.chapters.length,
                itemBuilder: (ctx, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[i],
                    decoration: InputDecoration(
                      labelText: 'Chapter ${i + 1}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final result = List.generate(
              widget.chapters.length,
              (i) => PdfChapter(
                title: _controllers[i].text.trim().isEmpty
                    ? 'Chapter ${i + 1}'
                    : _controllers[i].text.trim(),
                content: widget.chapters[i].content,
              ),
            );
            Navigator.pop(context, result);
          },
          child: const Text('Create All'),
        ),
      ],
    );
  }
}

Future<bool> _confirmDelete(BuildContext ctx, String name) async {
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dlgCtx) => AlertDialog(
      title: const Text('Delete Chapter'),
      content: Text('Delete "$name"? All chunks and saved outputs will also be removed.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dlgCtx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}
