import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/chapter.dart';
import '../models/chunk.dart';
import '../models/subject.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/subject_repository.dart';

class ImportExportService {
  static final instance = ImportExportService._();
  ImportExportService._();

  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();
  final _chunkRepo = ChunkRepository();

  static const _version = '1';

  // ── Export ──────────────────────────────────────────────────────────────────

  Future<void> export() async {
    final subjects = await _subjectRepo.getAll();
    final archive = Archive();

    final manifestSubjects = <Map<String, dynamic>>[];

    for (final subject in subjects) {
      final chapters = await _chapterRepo.getBySubject(subject.id);
      final chapterMaps = <Map<String, dynamic>>[];

      for (final chapter in chapters) {
        chapterMaps.add(chapter.toMap());

        final chunks = await _chunkRepo.getByChapter(chapter.id);
        if (chunks.isNotEmpty) {
          final chunksJson = jsonEncode(chunks.map((c) => c.toMap()).toList());
          final chunksBytes = utf8.encode(chunksJson);
          archive.addFile(
            ArchiveFile(
              'chunks/${chapter.id}.json',
              chunksBytes.length,
              chunksBytes,
            ),
          );
        }
      }

      manifestSubjects.add({...subject.toMap(), 'chapters': chapterMaps});
    }

    final manifest = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': manifestSubjects,
    };

    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw const _ExportException('Failed to create archive');
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = '${tempDir.path}/rightanswer_$stamp.zip';
    await File(zipPath).writeAsBytes(zipBytes);

    await Share.shareXFiles([
      XFile(zipPath, mimeType: 'application/zip'),
    ], subject: 'RightAnswer Backup');
  }

  // ── Import ──────────────────────────────────────────────────────────────────

  Future<
    ({
      int subjects,
      int chapters,
      int studyPlans,
      int exams,
      List<String> subjectIds,
      List<String> chapterIds,
      List<String> studyPlanIds,
      List<String> examIds,
    })
  >
  import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      throw const ImportCancelledException();
    }

    final path = result.files.first.path;
    if (path == null || !path.toLowerCase().endsWith('.zip')) {
      throw const ImportException('Please select a valid .zip file');
    }

    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (_) {
      throw const ImportException('Could not read the selected file');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ImportException('This file is not a valid .zip archive');
    }

    // Find manifest
    ArchiveFile? manifestFile;
    for (final f in archive) {
      if (f.name == 'manifest.json') {
        manifestFile = f;
        break;
      }
    }
    if (manifestFile == null) {
      throw const ImportException(
        'This file is not a valid RightAnswer backup',
      );
    }

    // Parse manifest
    final Map<String, dynamic> manifest;
    try {
      final jsonStr = utf8.decode(manifestFile.content as List<int>);
      manifest = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      throw const ImportException('Backup file is corrupted');
    }

    if (manifest['version'] != _version) {
      throw const ImportException('Backup version is not supported');
    }

    final subjectsList = manifest['subjects'];
    if (subjectsList == null || subjectsList is! List) {
      throw const ImportException('Backup file is corrupted');
    }

    // Build chunk map from archive
    final chunkMap = <String, List<Map<String, dynamic>>>{};
    for (final file in archive) {
      if (file.name.startsWith('chunks/') && file.name.endsWith('.json')) {
        final chapterId = file.name
            .replaceFirst('chunks/', '')
            .replaceFirst('.json', '');
        try {
          final jsonStr = utf8.decode(file.content as List<int>);
          final list = jsonDecode(jsonStr) as List<dynamic>;
          chunkMap[chapterId] = list.cast<Map<String, dynamic>>();
        } catch (_) {
          // Skip malformed chunk files
        }
      }
    }

    var importedSubjects = 0;
    var importedChapters = 0;
    final subjectIds = <String>[];
    final chapterIds = <String>[];
    const uuid = Uuid();

    for (final subjectData in subjectsList) {
      final sm = subjectData as Map<String, dynamic>;
      final newSubjectId = uuid.v4();

      final subject = Subject(
        id: newSubjectId,
        name: (sm['name'] as String?) ?? 'Imported Subject',
        createdAt:
            DateTime.tryParse(sm['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
      await _subjectRepo.insert(subject);
      importedSubjects++;
      subjectIds.add(newSubjectId);

      final chapters = (sm['chapters'] as List<dynamic>?) ?? [];
      for (final chapterData in chapters) {
        final cm = chapterData as Map<String, dynamic>;
        final oldChapterId = cm['id'] as String? ?? '';
        final newChapterId = uuid.v4();

        final chapter = Chapter(
          id: newChapterId,
          subjectId: newSubjectId,
          title: (cm['title'] as String?) ?? 'Imported Chapter',
          className: (cm['className'] as String?) ?? 'General',
          rawContent: (cm['rawContent'] as String?) ?? '',
          createdAt:
              DateTime.tryParse(cm['createdAt'] as String? ?? '') ??
              DateTime.now(),
        );
        await _chapterRepo.insert(chapter);
        importedChapters++;
        chapterIds.add(newChapterId);

        final chunks = chunkMap[oldChapterId] ?? [];
        if (chunks.isNotEmpty) {
          final chunkObjects = chunks.map((c) {
            return Chunk(
              id: uuid.v4(),
              chapterId: newChapterId,
              chunkIndex: (c['chunkIndex'] as int?) ?? 0,
              text: (c['text'] as String?) ?? '',
              page: c['page'] as int?,
              createdAt:
                  DateTime.tryParse(c['createdAt'] as String? ?? '') ??
                  DateTime.now(),
            );
          }).toList();
          await _chunkRepo.insertAll(chunkObjects);
        }
      }
    }

    return (
      subjects: importedSubjects,
      chapters: importedChapters,
      studyPlans: 0,
      exams: 0,
      subjectIds: subjectIds,
      chapterIds: chapterIds,
      studyPlanIds: const <String>[],
      examIds: const <String>[],
    );
  }

  // ── Per-subject / per-chapter export to bytes ─────────────────────────────

  Future<List<int>> exportSubjectToBytes(String subjectId) async {
    final subject = await _subjectRepo.getById(subjectId);
    if (subject == null) throw const _ExportException('Subject not found');

    final archive = Archive();
    final chapters = await _chapterRepo.getBySubject(subjectId);
    final chapterMaps = <Map<String, dynamic>>[];

    for (final chapter in chapters) {
      chapterMaps.add(chapter.toMap());
      final chunks = await _chunkRepo.getByChapter(chapter.id);
      if (chunks.isNotEmpty) {
        final chunksBytes = utf8.encode(
          jsonEncode(chunks.map((c) => c.toMap()).toList()),
        );
        archive.addFile(
          ArchiveFile(
            'chunks/${chapter.id}.json',
            chunksBytes.length,
            chunksBytes,
          ),
        );
      }
    }

    final manifest = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': [
        {...subject.toMap(), 'chapters': chapterMaps},
      ],
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw const _ExportException('Failed to create archive');
    }
    return zipBytes;
  }

  Future<List<int>> exportChapterToBytes(
    String chapterId,
    String subjectId,
  ) async {
    final subject = await _subjectRepo.getById(subjectId);
    final chapter = await _chapterRepo.getById(chapterId);
    if (chapter == null) {
      throw const _ExportException('Chapter not found');
    }

    final archive = Archive();
    final chunks = await _chunkRepo.getByChapter(chapterId);
    if (chunks.isNotEmpty) {
      final chunksBytes = utf8.encode(
        jsonEncode(chunks.map((c) => c.toMap()).toList()),
      );
      archive.addFile(
        ArchiveFile('chunks/$chapterId.json', chunksBytes.length, chunksBytes),
      );
    }

    final manifest = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': [
        {
          ...?subject?.toMap(),
          'id': subjectId,
          'name': subject?.name ?? 'Imported Subject',
          'chapters': [chapter.toMap()],
        },
      ],
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw const _ExportException('Failed to create archive');
    }
    return zipBytes;
  }

  /// Import from raw ZIP bytes (used when downloading from a share link).
  Future<
    ({
      int subjects,
      int chapters,
      int studyPlans,
      int exams,
      List<String> subjectIds,
      List<String> chapterIds,
      List<String> studyPlanIds,
      List<String> examIds,
    })
  >
  importFromBytes(List<int> bytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const ImportException('This file is not a valid .zip archive');
    }

    ArchiveFile? manifestFile;
    for (final f in archive) {
      if (f.name == 'manifest.json') {
        manifestFile = f;
        break;
      }
    }
    if (manifestFile == null) {
      throw const ImportException(
        'This file is not a valid RightAnswer backup',
      );
    }

    final Map<String, dynamic> manifest;
    try {
      manifest =
          jsonDecode(utf8.decode(manifestFile.content as List<int>))
              as Map<String, dynamic>;
    } catch (_) {
      throw const ImportException('Backup file is corrupted');
    }

    if (manifest['version'] != _version) {
      throw const ImportException('Backup version is not supported');
    }

    final subjectsList = manifest['subjects'];
    if (subjectsList == null || subjectsList is! List) {
      throw const ImportException('Backup file is corrupted');
    }

    final chunkMap = <String, List<Map<String, dynamic>>>{};
    for (final file in archive) {
      if (file.name.startsWith('chunks/') && file.name.endsWith('.json')) {
        final chapterId = file.name
            .replaceFirst('chunks/', '')
            .replaceFirst('.json', '');
        try {
          final list =
              jsonDecode(utf8.decode(file.content as List<int>))
                  as List<dynamic>;
          chunkMap[chapterId] = list.cast<Map<String, dynamic>>();
        } catch (_) {}
      }
    }

    var importedSubjects = 0;
    var importedChapters = 0;
    final subjectIds = <String>[];
    final chapterIds = <String>[];
    const uuid = Uuid();

    for (final subjectData in subjectsList) {
      final sm = subjectData as Map<String, dynamic>;
      final newSubjectId = uuid.v4();
      final subject = Subject(
        id: newSubjectId,
        name: (sm['name'] as String?) ?? 'Imported Subject',
        createdAt:
            DateTime.tryParse(sm['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
      await _subjectRepo.insert(subject);
      importedSubjects++;
      subjectIds.add(newSubjectId);

      for (final chapterData in (sm['chapters'] as List<dynamic>? ?? [])) {
        final cm = chapterData as Map<String, dynamic>;
        final oldChapterId = cm['id'] as String? ?? '';
        final newChapterId = uuid.v4();
        await _chapterRepo.insert(
          Chapter(
            id: newChapterId,
            subjectId: newSubjectId,
            title: (cm['title'] as String?) ?? 'Imported Chapter',
            className: (cm['className'] as String?) ?? 'General',
            rawContent: (cm['rawContent'] as String?) ?? '',
            createdAt:
                DateTime.tryParse(cm['createdAt'] as String? ?? '') ??
                DateTime.now(),
          ),
        );
        importedChapters++;
        chapterIds.add(newChapterId);
        final chunks = chunkMap[oldChapterId] ?? [];
        if (chunks.isNotEmpty) {
          await _chunkRepo.insertAll(
            chunks
                .map(
                  (c) => Chunk(
                    id: uuid.v4(),
                    chapterId: newChapterId,
                    chunkIndex: (c['chunkIndex'] as int?) ?? 0,
                    text: (c['text'] as String?) ?? '',
                    page: c['page'] as int?,
                    createdAt:
                        DateTime.tryParse(c['createdAt'] as String? ?? '') ??
                        DateTime.now(),
                  ),
                )
                .toList(),
          );
        }
      }
    }
    return (
      subjects: importedSubjects,
      chapters: importedChapters,
      studyPlans: 0,
      exams: 0,
      subjectIds: subjectIds,
      chapterIds: chapterIds,
      studyPlanIds: const <String>[],
      examIds: const <String>[],
    );
  }
}

class ImportException implements Exception {
  final String message;
  const ImportException(this.message);
  @override
  String toString() => message;
}

class ImportCancelledException implements Exception {
  const ImportCancelledException();
}

class _ExportException implements Exception {
  final String message;
  const _ExportException(this.message);
  @override
  String toString() => message;
}
