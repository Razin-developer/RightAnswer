import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../constants/tool_types.dart';

/// Handles all local push notifications for RightAnswer.
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ── Channel IDs ────────────────────────────────────────────────────────────
  static const _chGeneration = 'ra_generation';
  static const _chQueue = 'ra_queue';
  static const _chReminder = 'ra_reminder';

  // ── Fixed notification IDs ─────────────────────────────────────────────────
  static const int _idBase = 1000;
  static const int idOfflineQueued = 9001;
  static const int idQueueProcessed = 9002;
  static const int idConnRestored = 9003;
  static const int idDailyReminder = 9004;

  // Callback set by main.dart so notification taps can navigate the app.
  static void Function(String? payload)? onTap;

  // ── Initialization ─────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: darwin, macOS: darwin),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );

    if (Platform.isAndroid) await _createAndroidChannels();
    _initialized = true;
  }

  Future<void> _createAndroidChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _chGeneration, 'Generation Complete',
      description: 'Alerts when AI finishes generating content',
      importance: Importance.high,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _chQueue, 'Background Queue',
      description: 'Updates about offline queue and background processing',
      importance: Importance.defaultImportance,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _chReminder, 'Study Reminders',
      description: 'Daily reminders to study',
      importance: Importance.low,
    ));
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    if (!_initialized) await initialize();
    if (Platform.isAndroid) {
      final p = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await p?.requestNotificationsPermission() ?? false;
    }
    if (Platform.isIOS) {
      final p = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await p?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  // ── Show helpers ───────────────────────────────────────────────────────────

  Future<void> showGenerationComplete({
    required String toolType,
    required String chapterTitle,
  }) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.show(
      _idBase + toolType.hashCode.abs() % 100,
      '${ToolType.displayName(toolType)} ready ✓',
      chapterTitle,
      _details(_chGeneration, Importance.high),
      payload: 'saved_outputs',
    );
  }

  Future<void> showOfflineQueued(String toolType) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.show(
      idOfflineQueued,
      'Queued for later ⏳',
      '${ToolType.displayName(toolType)} will generate when you\'re back online',
      _details(_chQueue, Importance.defaultImportance),
      payload: 'queue',
    );
  }

  Future<void> showQueueProcessed(int count) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.show(
      idQueueProcessed,
      'Queue processed ✓',
      '$count ${count == 1 ? 'item' : 'items'} generated — tap to view',
      _details(_chQueue, Importance.defaultImportance),
      payload: 'saved_outputs',
    );
  }

  Future<void> showConnectivityRestored(int pendingCount) async {
    if (!_initialized || kIsWeb || pendingCount == 0) return;
    await _plugin.show(
      idConnRestored,
      'Back online 🌐',
      'Processing $pendingCount queued ${pendingCount == 1 ? 'request' : 'requests'}…',
      _details(_chQueue, Importance.low),
      payload: 'queue',
    );
  }

  // ── Daily reminder (scheduled) ─────────────────────────────────────────────

  Future<void> scheduleDailyReminder({required int hour, required int minute}) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.cancel(idDailyReminder);

    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now)) next = next.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      idDailyReminder,
      'Time to study! 📚',
      'Open RightAnswer and keep learning',
      next,
      _details(_chReminder, Importance.low),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'home',
    );
  }

  Future<void> cancelDailyReminder() async {
    if (!_initialized || kIsWeb) return;
    await _plugin.cancel(idDailyReminder);
  }

  Future<void> cancelAll() async {
    if (!_initialized || kIsWeb) return;
    await _plugin.cancelAll();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  NotificationDetails _details(String channelId, Importance importance) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId,
          importance: importance,
          priority: importance == Importance.high ? Priority.high : Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      );
}
