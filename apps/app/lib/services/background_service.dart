import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../repositories/chunk_repository.dart';
import '../repositories/queue_repository.dart';
import '../repositories/saved_output_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/notification_service.dart';
import '../services/openai_service.dart';
import '../services/queue_service.dart' show processQueueItems;
import '../services/retrieval_service.dart';

const _periodicTaskName = 'ra_queue_check';

/// Background task entry-point — must be a top-level function.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();

    // Re-create services fresh in this isolate (no shared state with main isolate)
    final chunkRepo = ChunkRepository();
    final settingsRepo = SettingsRepository();
    final usageLogRepo = UsageLogRepository();
    final savedOutputRepo = SavedOutputRepository();
    final queueRepo = QueueRepository();
    final retrieval = RetrievalService(chunkRepo);
    final openAI = OpenAIService(settingsRepo, usageLogRepo, retrieval);

    await NotificationService.instance.initialize();

    // Reset any stuck items from a previous crash
    await queueRepo.resetStuck();

    // Check if notifications for queue are enabled
    final notifyEnabled =
        await settingsRepo.get(SettingKeys.notifyOnQueueProcessed) ?? 'true';

    final processed = await processQueueItems(
      queueRepo: queueRepo,
      retrieval: retrieval,
      openAI: openAI,
      savedOutputRepo: savedOutputRepo,
    );

    if (processed == 0 || notifyEnabled != 'true') {
      // Cancel the "processing" notification if nothing was done
      await NotificationService.instance.cancelAll();
    }

    return true;
  });
}

class BackgroundService {
  BackgroundService._();

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher);
  }

  /// Register a periodic task that checks for pending queue items.
  /// Runs every 15 minutes (Android minimum) when network is available.
  static Future<void> registerPeriodicQueueCheck() async {
    await Workmanager().registerPeriodicTask(
      _periodicTaskName,
      _periodicTaskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(seconds: 30),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
