import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/subject.dart';
import '../models/chapter.dart';
import '../repositories/chapter_repository.dart';
import 'chapter_screen.dart';

class SubjectScreen extends StatefulWidget {
  final Subject subject;
  const SubjectScreen({super.key, required this.subject});

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  final _repo = ChapterRepository();
  List<Chapter> _chapters = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final chapters = await _repo.getBySubject(widget.subject.id);
    if (mounted) setState(() { _chapters = chapters; _loading = false; });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.name),
        centerTitle: false,
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
                    itemBuilder: (ctx, i) => _chapterCard(_chapters[i], i, theme),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addChapter,
        icon: const Icon(Icons.add),
        label: const Text('Add Chapter'),
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
            Text('Add your first chapter to start studying',
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

  Widget _chapterCard(Chapter c, int i, ThemeData theme) => Padding(
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
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                              fontSize: 15)),
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
                        Text(c.className,
                            style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
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
