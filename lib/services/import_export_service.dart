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
            ArchiveFile('chunks/${chapter.id}.json', chunksBytes.length, chunksBytes),
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
    if (zipBytes == null) throw const _ExportException('Failed to create archive');

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = '${tempDir.path}/rightanswer_$stamp.zip';
    await File(zipPath).writeAsBytes(zipBytes);

    await Share.shareXFiles(
      [XFile(zipPath, mimeType: 'application/zip')],
      subject: 'RightAnswer Backup',
    );
  }

  // ── Import ──────────────────────────────────────────────────────────────────

  Future<({int subjects, int chapters})> import() async {
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
      throw const ImportException('This file is not a valid RightAnswer backup');
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
    const uuid = Uuid();

    for (final subjectData in subjectsList) {
      final sm = subjectData as Map<String, dynamic>;
      final newSubjectId = uuid.v4();

      final subject = Subject(
        id: newSubjectId,
        name: (sm['name'] as String?) ?? 'Imported Subject',
        createdAt:
            DateTime.tryParse(sm['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
      await _subjectRepo.insert(subject);
      importedSubjects++;

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
              DateTime.tryParse(cm['createdAt'] as String? ?? '') ?? DateTime.now(),
        );
        await _chapterRepo.insert(chapter);
        importedChapters++;

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

    return (subjects: importedSubjects, chapters: importedChapters);
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
