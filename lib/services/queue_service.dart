import 'package:uuid/uuid.dart';
import '../models/queued_request.dart';
import '../models/saved_output.dart';
import '../repositories/chunk_repository.dart';
import '../repositories/queue_repository.dart';
import '../repositories/saved_output_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/notification_service.dart';
import '../services/openai_service.dart';
import '../services/retrieval_service.dart';

/// Manages the offline request queue and drives foreground processing.
class QueueService {
  static final QueueService instance = QueueService._();
  QueueService._();

  final _queueRepo = QueueRepository();
  final _chunkRepo = ChunkRepository();
  final _settingsRepo = SettingsRepository();
  final _usageLogRepo = UsageLogRepository();
  final _savedOutputRepo = SavedOutputRepository();

  late final RetrievalService _retrieval;
  late final OpenAIService _openAI;

  bool _processing = false;

  // ValueNotifier so UI can reactively show the pending count badge.
  int _pendingCount = 0;
  int get pendingCount => _pendingCount;

  final List<void Function()> _listeners = [];
  void addListener(void Function() l) => _listeners.add(l);
  void removeListener(void Function() l) => _listeners.remove(l);
  void _notify() {
    for (final l in _listeners) { l(); }
  }

  Future<void> initialize() async {
    _retrieval = RetrievalService(_chunkRepo);
    _openAI = OpenAIService(_settingsRepo, _usageLogRepo, _retrieval);
    // Reset any items that got stuck as 'processing' from a previous crash
    await _queueRepo.resetStuck();
    await _refreshCount();
  }

  Future<void> _refreshCount() async {
    _pendingCount = await _queueRepo.countPending();
    _notify();
  }

  /// Enqueue a request to be generated when online.
  Future<void> enqueue(QueuedRequest req) async {
    await _queueRepo.insert(req);
    await _refreshCount();
  }

  Future<void> retry(String id) async {
    await _queueRepo.retry(id);
    await _refreshCount();
  }

  Future<void> delete(String id) async {
    await _queueRepo.delete(id);
    await _refreshCount();
  }

  Future<void> clearDone() async {
    await _queueRepo.clearDone();
    await _refreshCount();
  }

  Future<List<QueuedRequest>> getAll() => _queueRepo.getAll();

  /// Process all pending items. Safe to call concurrently (guarded by [_processing]).
  Future<void> processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      await _processQueueItems(
        queueRepo: _queueRepo,
        retrieval: _retrieval,
        openAI: _openAI,
        savedOutputRepo: _savedOutputRepo,
        onProgress: _refreshCount,
      );
    } finally {
      _processing = false;
      await _refreshCount();
    }
  }
}

// ── Top-level function usable from both foreground and background isolate ─────

Future<int> processQueueItems({
  required QueueRepository queueRepo,
  required RetrievalService retrieval,
  required OpenAIService openAI,
  required SavedOutputRepository savedOutputRepo,
  Future<void> Function()? onProgress,
}) async {
  final pending = await queueRepo.getPending();
  int processed = 0;

  for (final req in pending) {
    try {
      await queueRepo.updateStatus(req.id, 'processing');
      if (onProgress != null) await onProgress();

      final chunks = await retrieval.searchChapter(req.chapterId, req.question ?? '');
      final result = await openAI.generateFromContext(
        toolType: req.toolType,
        question: req.question,
        contextChunks: chunks.map((c) => c.text).toList(),
        language: req.language,
        gradeLevel: req.gradeLevel,
        tone: req.tone,
        outputLength: req.outputLength,
      );

      await savedOutputRepo.insert(SavedOutput(
        id: const Uuid().v4(),
        subjectId: req.subjectId,
        chapterId: req.chapterId,
        toolType: req.toolType,
        question: req.question,
        answer: result.answer,
        language: req.language,
        usedChunkIds: chunks.map((c) => c.id).toList(),
        createdAt: DateTime.now(),
      ));

      await queueRepo.updateStatus(req.id, 'done');
      processed++;
    } catch (e) {
      await queueRepo.updateStatus(req.id, 'failed', error: e.toString());
    }
    if (onProgress != null) await onProgress();
  }

  if (processed > 0) {
    await NotificationService.instance.showQueueProcessed(processed);
  }
  return processed;
}

// Private alias used inside QueueService
Future<void> _processQueueItems({
  required QueueRepository queueRepo,
  required RetrievalService retrieval,
  required OpenAIService openAI,
  required SavedOutputRepository savedOutputRepo,
  Future<void> Function()? onProgress,
}) => processQueueItems(
      queueRepo: queueRepo,
      retrieval: retrieval,
      openAI: openAI,
      savedOutputRepo: savedOutputRepo,
      onProgress: onProgress,
    );
