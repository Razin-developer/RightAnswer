import '../models/chapter.dart';
import '../models/subject.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/subject_repository.dart';
import 'api_service.dart';
import 'connectivity_service.dart';

/// Mirrors the backend's textbook catalog (GET /api/catalog — subjects and
/// their chapters from the currently-active textbook version) into the local
/// SQLite database, so the optional chapter picker (chat "+" menu, exam
/// creation, study plan creation) has something to show without a network
/// round trip every time it opens.
///
/// This is purely additive/background: retrieval on the backend already
/// works globally without a chapter filter, so a failed or skipped sync must
/// never block or error out any user-facing flow. If the device is offline
/// or the request fails, we silently give up and try again on next launch.
class CatalogSyncService {
  static final CatalogSyncService instance = CatalogSyncService._();
  CatalogSyncService._();

  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();

  bool _syncing = false;

  /// Fire-and-forget entry point for app startup. Does not await network
  /// I/O on the caller's behalf — callers should not `await` this if they
  /// want it to run in the background (it returns a Future only so callers
  /// that *do* want to await, e.g. tests, still can).
  Future<void> syncInBackground() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _sync();
    } catch (_) {
      // Never let a catalog sync failure surface to the user — retry
      // silently on the next app launch.
    } finally {
      _syncing = false;
    }
  }

  Future<void> _sync() async {
    if (!ConnectivityService.instance.isOnline) return;

    final Map<String, dynamic> data;
    try {
      data = await ApiService.instance.get('/api/catalog');
    } catch (_) {
      // Offline, timed out, or backend error — skip silently, retry later.
      return;
    }

    final rawSubjects = data['subjects'];
    if (rawSubjects is! List) return;

    final now = DateTime.now();
    final subjects = <Subject>[];
    final chapters = <Chapter>[];

    for (final entry in rawSubjects) {
      if (entry is! Map) continue;
      final subjectId = entry['id']?.toString();
      final subjectName = entry['name']?.toString();
      if (subjectId == null || subjectId.isEmpty || subjectName == null) {
        continue;
      }
      subjects.add(Subject(id: subjectId, name: subjectName, createdAt: now));

      final rawParts = entry['parts'];
      if (rawParts is! List) continue;
      for (final partEntry in rawParts) {
        if (partEntry is! Map) continue;
        final partLabel = partEntry['label']?.toString();
        final rawChapters = partEntry['chapters'];
        if (rawChapters is! List) continue;
        for (final chapterEntry in rawChapters) {
          if (chapterEntry is! Map) continue;
          final chapterId = chapterEntry['id']?.toString();
          final chapterTitle = chapterEntry['title']?.toString();
          if (chapterId == null || chapterId.isEmpty || chapterTitle == null) {
            continue;
          }
          final number = chapterEntry['number'];
          chapters.add(
            Chapter(
              id: chapterId,
              subjectId: subjectId,
              title: chapterTitle,
              className: '',
              number: number is num ? number.toInt() : 0,
              partLabel: partLabel,
              createdAt: now,
            ),
          );
        }
      }
    }

    if (subjects.isEmpty) return;

    await _subjectRepo.upsertAll(subjects);
    await _chapterRepo.upsertAll(chapters);
  }
}
