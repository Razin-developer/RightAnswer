import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/chapter.dart';
import '../models/subject.dart';
import '../repositories/subject_repository.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/chunk_repository.dart';
import '../services/connectivity_service.dart';
import '../services/import_export_service.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_logo.dart';
import 'chapter_screen.dart';
import 'queue_screen.dart';
import 'subject_screen.dart';
import 'saved_outputs_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialSubjectId;
  final String? initialChapterId;

  const HomeScreen({super.key, this.initialSubjectId, this.initialChapterId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = SubjectRepository();
  final _chapterRepo = ChapterRepository();
  final _chunkRepo = ChunkRepository();

  List<Subject> _subjects = [];
  Map<String, int> _chapterCounts = {};
  Map<String, int> _chunkCounts = {};
  bool _loading = true;
  bool _exporting = false;
  bool _importing = false;
  bool _didConsumeInitialLink = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final subjects = await _repo.getAll();

    // Load chapter counts and collect all chapter IDs in one pass
    final chapterCounts = <String, int>{};
    final allChapterIds = <String>[];
    final subjectChapters = <String, List<String>>{};
    for (final s in subjects) {
      final chapters = await _chapterRepo.getBySubject(s.id);
      chapterCounts[s.id] = chapters.length;
      final ids = chapters.map((c) => c.id).toList();
      allChapterIds.addAll(ids);
      subjectChapters[s.id] = ids;
    }

    // Load chunk counts for all chapters in one query
    final chunkCounts = await _chunkRepo.countsByChapters(allChapterIds);

    // Aggregate chunks per subject (no extra queries)
    final subjectChunkCounts = <String, int>{};
    for (final s in subjects) {
      final ids = subjectChapters[s.id] ?? [];
      subjectChunkCounts[s.id] = ids.fold(
        0,
        (t, id) => t + (chunkCounts[id] ?? 0),
      );
    }

    if (mounted) {
      setState(() {
        _subjects = subjects;
        _chapterCounts = chapterCounts;
        _chunkCounts = subjectChunkCounts;
        _loading = false;
      });
    }

    if (_didConsumeInitialLink) {
      return;
    }
    final initialSubjectId = widget.initialSubjectId;
    final initialChapterId = widget.initialChapterId;
    if (initialSubjectId == null && initialChapterId == null) {
      _didConsumeInitialLink = true;
      return;
    }

    _didConsumeInitialLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      Subject? subject;
      Chapter? chapter;

      if (initialChapterId != null) {
        chapter = await _chapterRepo.getById(initialChapterId);
        if (chapter != null) {
          subject = await _repo.getById(chapter.subjectId);
        }
      } else if (initialSubjectId != null) {
        subject = await _repo.getById(initialSubjectId);
      }

      if (!mounted) {
        return;
      }

      if (subject != null && chapter != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChapterScreen(chapter: chapter!, subject: subject!),
          ),
        );
        return;
      }

      if (subject != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SubjectScreen(subject: subject!)),
        );
      }
    });
  }

  Future<void> _addSubject() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddDialog(
        title: 'New Subject',
        hint: 'e.g. Physics, Biology, History',
        label: 'Subject name',
        controller: ctrl,
      ),
    );
    if (name == null || name.isEmpty) return;
    await _repo.insert(
      Subject(id: Uuid().v4(), name: name, createdAt: DateTime.now()),
    );
    _load();
  }

  Future<void> _deleteSubject(Subject s) async {
    final ok = await _confirmDelete(
      context,
      'Delete Subject',
      '"${s.name}" and all its chapters will be permanently removed.',
    );
    if (!ok) return;
    await _repo.delete(s.id);
    _load();
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await ImportExportService.instance.export();
    } catch (e) {
      if (mounted) AppFeedback.showErrorToast(context, 'Export failed');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await ImportExportService.instance.import();
      if (!mounted) return;
      AppFeedback.showSuccessToast(
        context,
        'Imported ${result.subjects} subject${result.subjects != 1 ? 's' : ''}, ${result.chapters} chapter${result.chapters != 1 ? 's' : ''}',
      );
      _load();
    } on ImportCancelledException {
      // User cancelled picker — no feedback
    } on ImportException catch (e) {
      if (mounted) AppFeedback.showErrorToast(context, e.message);
    } catch (_) {
      if (mounted) AppFeedback.showErrorToast(context, 'Import failed');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalChapters = _chapterCounts.values.fold(0, (a, b) => a + b);
    final readyChapters = _subjects
        .where((s) => (_chunkCounts[s.id] ?? 0) > 0)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            AppLogo(size: 28),
            SizedBox(width: 10),
            Text('RightAnswer'),
          ],
        ),
        actions: [
          ConnectivityChip(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QueueScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Saved Outputs',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SavedOutputsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ).then((_) => setState(() {})),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _OfflineBanner(
            onViewQueue: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QueueScreen()),
            ),
          ),
          // Stats bar (only when content exists)
          if (!_loading && _subjects.isNotEmpty)
            _StatsBar(
              subjectCount: _subjects.length,
              chapterCount: totalChapters,
              readyCount: readyChapters,
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _subjects.isEmpty
                ? _emptyState(theme)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: _subjects.length,
                      itemBuilder: (ctx, i) =>
                          _subjectCard(_subjects[i], i, theme),
                    ),
                  ),
          ),
          // Import / Export row
          _ImportExportBar(
            onImport: _import,
            onExport: _export,
            importing: _importing,
            exporting: _exporting,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSubject,
        icon: const Icon(Icons.add),
        label: const Text('Add Subject'),
      ),
    );
  }

  Widget _emptyState(ThemeData theme) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.library_books_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Your AI Study Assistant',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload your textbooks. Ask anything. Get instant, accurate answers.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 28),
          // 3-step guide
          _StepRow(
            icon: Icons.add_circle_outline,
            color: theme.colorScheme.primary,
            text: 'Add a subject',
          ),
          const SizedBox(height: 12),
          _StepRow(
            icon: Icons.upload_file_outlined,
            color: const Color(0xFF7C3AED),
            text: 'Upload chapter content',
          ),
          const SizedBox(height: 12),
          _StepRow(
            icon: Icons.chat_bubble_outline_rounded,
            color: const Color(0xFF059669),
            text: 'Ask the AI — get answers from your material',
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _addSubject,
            icon: const Icon(Icons.add),
            label: const Text('Add Subject'),
          ),
        ],
      ),
    ),
  );

  Widget _subjectCard(Subject s, int i, ThemeData theme) {
    const accentColors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFFDC2626),
      Color(0xFFD97706),
      Color(0xFF0891B2),
    ];
    final color = accentColors[i % accentColors.length];
    final chapters = _chapterCounts[s.id] ?? 0;
    final hasContent = (_chunkCounts[s.id] ?? 0) > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SubjectScreen(subject: s)),
          ).then((_) => _load()),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.subject, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.45,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$chapters chapter${chapters != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          if (hasContent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF059669,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'AI Ready',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  onSelected: (v) {
                    if (v == 'delete') _deleteSubject(s);
                  },
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

// ── Stats bar ─────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final int subjectCount;
  final int chapterCount;
  final int readyCount;

  const _StatsBar({
    required this.subjectCount,
    required this.chapterCount,
    required this.readyCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          _StatChip(
            label: '$subjectCount subject${subjectCount != 1 ? 's' : ''}',
          ),
          const SizedBox(width: 16),
          _StatChip(
            label: '$chapterCount chapter${chapterCount != 1 ? 's' : ''}',
          ),
          const Spacer(),
          if (readyCount > 0)
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF059669),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$readyCount AI-ready',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF059669),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  const _StatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}

// ── Step row (empty state guide) ──────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _StepRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Import / Export bar ───────────────────────────────────────────────────────

class _ImportExportBar extends StatelessWidget {
  final VoidCallback onImport;
  final VoidCallback onExport;
  final bool importing;
  final bool exporting;

  const _ImportExportBar({
    required this.onImport,
    required this.onExport,
    required this.importing,
    required this.exporting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: importing ? null : onImport,
                child: importing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Import'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: exporting ? null : onExport,
                child: exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Export'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatefulWidget {
  final VoidCallback onViewQueue;
  const _OfflineBanner({required this.onViewQueue});

  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.isOnlineNotifier.addListener(_rebuild);
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnlineNotifier.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (ConnectivityService.instance.isOnline) return const SizedBox.shrink();
    return GestureDetector(
      onTap: widget.onViewQueue,
      child: Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 15, color: Colors.orange),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'You\'re offline — study tools will be queued',
                style: TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: Colors.orange),
          ],
        ),
      ),
    );
  }
}

// ── Shared dialog ────────────────────────────────────────────────────────────

class _AddDialog extends StatelessWidget {
  final String title;
  final String label;
  final String hint;
  final TextEditingController controller;

  const _AddDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label, hintText: hint),
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

Future<bool> _confirmDelete(BuildContext ctx, String title, String body) async {
  final result = await showDialog<bool>(
    context: ctx,
    builder: (dlgCtx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dlgCtx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(dlgCtx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return result == true;
}
