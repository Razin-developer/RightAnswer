import 'package:flutter/material.dart';

import '../models/chapter.dart';
import '../models/subject.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/subject_repository.dart';

/// A chapter chosen from [showChapterPickerSheet], carrying just enough to
/// scope an AI request (`chapterIds: [chapterId]`) and to render a label
/// wherever the selection needs to be shown back to the user.
class ChapterPickerResult {
  final String chapterId;
  final String chapterLabel;
  final String subjectName;

  const ChapterPickerResult({
    required this.chapterId,
    required this.chapterLabel,
    required this.subjectName,
  });
}

/// Opens the shared, optional chapter/subject picker as a bottom sheet.
/// Returns the selected chapter, or null if the user dismissed it without
/// picking one. Selection is always optional — callers should treat a null
/// result as "search globally", which is the existing default behavior.
Future<ChapterPickerResult?> showChapterPickerSheet(BuildContext context) {
  return showModalBottomSheet<ChapterPickerResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _ChapterPickerSheet(),
  );
}

/// Small persistent pill shown near a prompt box once a chapter has been
/// picked, e.g. "Chapter 3: Force and Motion ×". Reused identically across
/// chat, exam creation, and study plan creation.
class SelectedChapterChip extends StatelessWidget {
  final String label;
  final VoidCallback onClear;

  const SelectedChapterChip({
    super.key,
    required this.label,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterPickerSheet extends StatefulWidget {
  const _ChapterPickerSheet();

  @override
  State<_ChapterPickerSheet> createState() => _ChapterPickerSheetState();
}

class _ChapterPickerSheetState extends State<_ChapterPickerSheet> {
  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  List<Subject> _subjects = [];
  Map<String, List<Chapter>> _chaptersBySubject = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final subjects = await _subjectRepo.getAll();
    final byId = <String, List<Chapter>>{};
    for (final subject in subjects) {
      byId[subject.id] = await _chapterRepo.getBySubject(subject.id);
    }
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _chaptersBySubject = byId;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchCtrl.text.trim().toLowerCase();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Scope to a chapter',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.45,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Leave nothing selected to search across the whole textbook.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search subject or chapter',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 440),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : _subjects.isEmpty
                      ? _EmptyCatalog(theme: theme)
                      : _buildList(theme, query),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, String query) {
    if (query.isEmpty) {
      // Grouped, expandable-by-subject view — the default when the user
      // hasn't typed anything yet.
      final subjectsWithChapters = _subjects
          .where((s) => (_chaptersBySubject[s.id] ?? const []).isNotEmpty)
          .toList();
      if (subjectsWithChapters.isEmpty) {
        return _EmptyCatalog(theme: theme);
      }
      return ListView.builder(
        shrinkWrap: true,
        itemCount: subjectsWithChapters.length,
        itemBuilder: (context, index) {
          final subject = subjectsWithChapters[index];
          final chapters = _chaptersBySubject[subject.id] ?? const [];
          return Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: Text(
                subject.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(
                '${chapters.length} chapter${chapters.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              children: chapters
                  .map((c) => _ChapterTile(chapter: c, subject: subject))
                  .toList(),
            ),
          );
        },
      );
    }

    // Flat, filtered view while searching.
    final results = <(Chapter, Subject)>[];
    for (final subject in _subjects) {
      final matchesSubject = subject.name.toLowerCase().contains(query);
      for (final chapter in _chaptersBySubject[subject.id] ?? const []) {
        if (matchesSubject ||
            chapter.title.toLowerCase().contains(query) ||
            chapter.displayLabel.toLowerCase().contains(query)) {
          results.add((chapter, subject));
        }
      }
    }

    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'No chapters found',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
      itemBuilder: (context, index) {
        final (chapter, subject) = results[index];
        return _ChapterTile(chapter: chapter, subject: subject);
      },
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final Chapter chapter;
  final Subject subject;

  const _ChapterTile({required this.chapter, required this.subject});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(chapter.displayLabel, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        subject.name,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      onTap: () => Navigator.pop(
        context,
        ChapterPickerResult(
          chapterId: chapter.id,
          chapterLabel: chapter.displayLabel,
          subjectName: subject.name,
        ),
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  final ThemeData theme;
  const _EmptyCatalog({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 28,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 10),
          Text(
            'Catalog not synced yet',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect to the internet and reopen the app to load subjects and chapters.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
