import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/chapter.dart';
import '../models/chunk.dart';
import '../models/exam.dart';
import '../models/exam_question.dart';
import '../models/subject.dart';
import '../models/study_day.dart';
import '../models/study_plan.dart';
import '../models/study_task.dart';
import '../repositories/chapter_repository.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/exam_question_repository.dart';
import '../repositories/exam_repository.dart';
import '../repositories/subject_repository.dart';
import '../repositories/study_day_repository.dart';
import '../repositories/study_plan_repository.dart';
import '../repositories/study_task_repository.dart';

class ImportExportService {
  static final instance = ImportExportService._();
  ImportExportService._();

  final _subjectRepo = SubjectRepository();
  final _chapterRepo = ChapterRepository();
  final _chunkRepo = ChunkRepository();
  final _planRepo = StudyPlanRepository();
  final _dayRepo = StudyDayRepository();
  final _taskRepo = StudyTaskRepository();
  final _examRepo = ExamRepository();
  final _questionRepo = ExamQuestionRepository();

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

    final manifestStudyPlans = <Map<String, dynamic>>[];
    for (final plan in await _planRepo.getAll()) {
      final days = await _dayRepo.getByPlan(plan.id);
      final tasks = await _taskRepo.getByPlan(plan.id);
      manifestStudyPlans.add({
        ...plan.toMap(),
        'days': days.map((day) => day.toMap()).toList(),
        'tasks': tasks.map((task) => task.toMap()).toList(),
      });
    }

    final manifestExams = <Map<String, dynamic>>[];
    for (final exam in await _examRepo.getAll()) {
      final questions = await _questionRepo.getByExam(exam.id);
      manifestExams.add({
        ...exam.toMap(),
        'questions': questions.map((question) => question.toMap()).toList(),
      });
    }

    final manifest = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': manifestSubjects,
      'studyPlans': manifestStudyPlans,
      'exams': manifestExams,
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

    return _importArchive(archive);
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

  Future<List<int>> exportStudyPlanToBytes(String planId) async {
    final plan = await _planRepo.getById(planId);
    if (plan == null) {
      throw const _ExportException('Study plan not found');
    }

    final days = await _dayRepo.getByPlan(planId);
    final tasks = await _taskRepo.getByPlan(planId);
    final manifest = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': const <Map<String, dynamic>>[],
      'studyPlans': [
        {
          ...plan.toMap(),
          'days': days.map((day) => day.toMap()).toList(),
          'tasks': tasks.map((task) => task.toMap()).toList(),
        },
      ],
      'exams': const <Map<String, dynamic>>[],
    };
    return _encodeManifest(manifest);
  }

  Future<List<int>> exportExamToBytes(String examId) async {
    final exam = await _examRepo.getById(examId);
    if (exam == null) {
      throw const _ExportException('Exam not found');
    }

    final questions = await _questionRepo.getByExam(examId);
    final manifest = {
      'version': _version,
      'exportedAt': DateTime.now().toIso8601String(),
      'subjects': const <Map<String, dynamic>>[],
      'studyPlans': const <Map<String, dynamic>>[],
      'exams': [
        {
          ...exam.toMap(),
          'questions': questions.map((question) => question.toMap()).toList(),
        },
      ],
    };
    return _encodeManifest(manifest);
  }

  List<int> _encodeManifest(Map<String, dynamic> manifest) {
    final archive = Archive();
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

    return _importArchive(archive);
  }

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
  _importArchive(Archive archive) async {
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

    final rawSubjects = manifest['subjects'];
    final rawStudyPlans = manifest['studyPlans'];
    final rawExams = manifest['exams'];
    if ((rawSubjects != null && rawSubjects is! List) ||
        (rawStudyPlans != null && rawStudyPlans is! List) ||
        (rawExams != null && rawExams is! List)) {
      throw const ImportException('Backup file is corrupted');
    }

    final subjectsList = (rawSubjects as List?) ?? const <dynamic>[];
    final studyPlanList = (rawStudyPlans as List?) ?? const <dynamic>[];
    final examList = (rawExams as List?) ?? const <dynamic>[];

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
    var importedStudyPlans = 0;
    var importedExams = 0;
    final subjectIds = <String>[];
    final chapterIds = <String>[];
    final studyPlanIds = <String>[];
    final examIds = <String>[];
    final subjectIdMap = <String, String>{};
    final chapterIdMap = <String, String>{};
    const uuid = Uuid();

    for (final subjectData in subjectsList) {
      final sm = subjectData as Map<String, dynamic>;
      final oldSubjectId = sm['id'] as String? ?? '';
      final newSubjectId = uuid.v4();
      if (oldSubjectId.isNotEmpty) {
        subjectIdMap[oldSubjectId] = newSubjectId;
      }

      await _subjectRepo.insert(
        Subject(
          id: newSubjectId,
          name: (sm['name'] as String?) ?? 'Imported Subject',
          createdAt:
              DateTime.tryParse(sm['createdAt'] as String? ?? '') ??
              DateTime.now(),
        ),
      );
      importedSubjects++;
      subjectIds.add(newSubjectId);

      for (final chapterData in (sm['chapters'] as List<dynamic>? ?? [])) {
        final cm = chapterData as Map<String, dynamic>;
        final oldChapterId = cm['id'] as String? ?? '';
        final newChapterId = uuid.v4();
        if (oldChapterId.isNotEmpty) {
          chapterIdMap[oldChapterId] = newChapterId;
        }

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

        final chunks = chunkMap[oldChapterId] ?? const [];
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

    for (final planData in studyPlanList) {
      final pm = Map<String, dynamic>.from(planData as Map);
      final newPlanId = uuid.v4();
      final oldSubjectId = pm['subjectId'] as String?;
      final oldChapterIds = _decodeStringList(pm['chapterIds']);
      pm['id'] = newPlanId;
      pm['subjectId'] = oldSubjectId == null
          ? null
          : subjectIdMap[oldSubjectId] ?? oldSubjectId;
      pm['chapterIds'] = jsonEncode(
        oldChapterIds.map((id) => chapterIdMap[id] ?? id).toList(),
      );
      await _planRepo.insert(StudyPlan.fromMap(pm));
      importedStudyPlans++;
      studyPlanIds.add(newPlanId);

      final dayIdMap = <String, String>{};
      for (final dayData in (pm['days'] as List<dynamic>? ?? [])) {
        final dm = Map<String, dynamic>.from(dayData as Map);
        final oldDayId = dm['id'] as String? ?? '';
        final newDayId = uuid.v4();
        if (oldDayId.isNotEmpty) {
          dayIdMap[oldDayId] = newDayId;
        }
        dm['id'] = newDayId;
        dm['planId'] = newPlanId;
        await _dayRepo.insert(StudyDay.fromMap(dm));
      }

      for (final taskData in (pm['tasks'] as List<dynamic>? ?? [])) {
        final tm = Map<String, dynamic>.from(taskData as Map);
        final oldDayId = tm['dayId'] as String? ?? '';
        final oldChapterId = tm['chapterId'] as String?;
        tm['id'] = uuid.v4();
        tm['planId'] = newPlanId;
        tm['dayId'] = dayIdMap[oldDayId] ?? oldDayId;
        tm['chapterId'] = oldChapterId == null
            ? null
            : chapterIdMap[oldChapterId] ?? oldChapterId;
        await _taskRepo.insert(StudyTask.fromMap(tm));
      }
    }

    for (final examData in examList) {
      final em = Map<String, dynamic>.from(examData as Map);
      final newExamId = uuid.v4();
      final oldSubjectId = em['subjectId'] as String?;
      final oldChapterIds = _splitIds(em['chapterIds'] as String?);
      em['id'] = newExamId;
      em['subjectId'] = oldSubjectId == null
          ? null
          : subjectIdMap[oldSubjectId] ?? oldSubjectId;
      em['chapterIds'] = oldChapterIds
          .map((id) => chapterIdMap[id] ?? id)
          .where((id) => id.isNotEmpty)
          .join('||');
      await _examRepo.insert(Exam.fromMap(em));
      importedExams++;
      examIds.add(newExamId);

      for (final questionData in (em['questions'] as List<dynamic>? ?? [])) {
        final qm = Map<String, dynamic>.from(questionData as Map);
        qm['id'] = uuid.v4();
        qm['examId'] = newExamId;
        qm['userAnswer'] = null;
        await _questionRepo.insert(ExamQuestion.fromMap(qm));
      }
    }

    return (
      subjects: importedSubjects,
      chapters: importedChapters,
      studyPlans: importedStudyPlans,
      exams: importedExams,
      subjectIds: subjectIds,
      chapterIds: chapterIds,
      studyPlanIds: studyPlanIds,
      examIds: examIds,
    );
  }

  List<String> _decodeStringList(dynamic raw) {
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }
    return const <String>[];
  }

  List<String> _splitIds(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    return raw.split('||').where((item) => item.isNotEmpty).toList();
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
