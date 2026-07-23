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

  // Browse navigation: subject -> part (only when a subject has more than
  // one distinct part label) -> chapter. Search bypasses this entirely and
  // always shows a flat, filtered list.
  Subject? _drilldownSubject;
  String? _drilldownPart;

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

  /// Distinct part labels for a subject's chapters, in first-seen order.
  /// A subject with a single (or no) part label has nothing worth splitting
  /// into a separate "select part" step.
  List<String?> _partsFor(Subject subject) {
    final chapters = _chaptersBySubject[subject.id] ?? const [];
    final seen = <String?>[];
    for (final chapter in chapters) {
      if (!seen.contains(chapter.partLabel)) seen.add(chapter.partLabel);
    }
    return seen;
  }

  bool _hasMultipleParts(Subject subject) => _partsFor(subject).length > 1;

  void _openSubject(Subject subject) {
    if (_hasMultipleParts(subject)) {
      setState(() {
        _drilldownSubject = subject;
        _drilldownPart = null;
      });
    } else {
      final parts = _partsFor(subject);
      setState(() {
        _drilldownSubject = subject;
        _drilldownPart = parts.isEmpty ? null : parts.first;
      });
    }
  }

  void _backOnePage() {
    setState(() {
      if (_drilldownPart != null && _hasMultipleParts(_drilldownSubject!)) {
        _drilldownPart = null;
      } else {
        _drilldownSubject = null;
        _drilldownPart = null;
      }
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
                  if (query.isEmpty && _drilldownSubject != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: IconButton(
                        onPressed: _backOnePage,
                        icon: const Icon(Icons.arrow_back_rounded),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      query.isNotEmpty
                          ? 'Scope to a chapter'
                          : _drilldownSubject == null
                          ? 'Select a subject'
                          : _drilldownPart == null
                          ? _drilldownSubject!.name
                          : '${_drilldownSubject!.name} · $_drilldownPart',
                      overflow: TextOverflow.ellipsis,
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
              // Fixed height regardless of how many subjects/parts/chapters
              // are showing — a picker whose sheet height jumped around
              // with content (a handful of subjects vs. a full chapter
              // list) felt unstable. Short content just leaves empty space
              // below it; long content scrolls within this box.
              SizedBox(
                height: 440,
                child: _loading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _subjects.isEmpty
                    ? _EmptyCatalog(theme: theme)
                    : _buildList(theme, query),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme, String query) {
    if (query.isEmpty) {
      // Subject -> Part -> Chapter browse, driven by _drilldownSubject /
      // _drilldownPart. Subjects with only one part skip straight to their
      // chapter list (see _openSubject).
      final subjectsWithChapters = _subjects
          .where((s) => (_chaptersBySubject[s.id] ?? const []).isNotEmpty)
          .toList();
      if (subjectsWithChapters.isEmpty) {
        return _EmptyCatalog(theme: theme);
      }

      if (_drilldownSubject == null) {
        return ListView.separated(
          shrinkWrap: true,
          itemCount: subjectsWithChapters.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
          itemBuilder: (context, index) {
            final subject = subjectsWithChapters[index];
            final chapters = _chaptersBySubject[subject.id] ?? const [];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                subject.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${chapters.length} chapter${chapters.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openSubject(subject),
            );
          },
        );
      }

      final subject = _drilldownSubject!;
      // `_drilldownPart == null` is ambiguous on its own: it means both
      // "haven't picked a part yet" AND "this subject's only part has no
      // label" (Malayalam ET/BET, ICT, ... — one book, not split into
      // parts). Only show the part-picker when there's actually more than
      // one part to choose from — otherwise a single-part subject would
      // show a dead-end "All chapters" tile whose tap sets _drilldownPart
      // to the same null value, so the UI never advances.
      final needsPartChoice = _drilldownPart == null && _hasMultipleParts(subject);
      if (needsPartChoice) {
        final parts = _partsFor(subject);
        return ListView.separated(
          shrinkWrap: true,
          itemCount: parts.length,
          separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
          itemBuilder: (context, index) {
            final part = parts[index];
            final count = (_chaptersBySubject[subject.id] ?? const [])
                .where((c) => c.partLabel == part)
                .length;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.menu_book_outlined),
              title: Text(
                part ?? 'All chapters',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '$count chapter${count == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => setState(() => _drilldownPart = part),
            );
          },
        );
      }

      final chapters = (_chaptersBySubject[subject.id] ?? const [])
          .where((c) => c.partLabel == _drilldownPart)
          .toList();
      return ListView.separated(
        shrinkWrap: true,
        itemCount: chapters.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: theme.dividerColor),
        itemBuilder: (context, index) =>
            _ChapterTile(chapter: chapters[index], subject: subject),
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
