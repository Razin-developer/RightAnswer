import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import '../constants/tool_types.dart';
import '../models/study_day.dart';
import '../models/study_plan.dart';
import '../models/study_task.dart';
import '../repositories/study_day_repository.dart';
import '../repositories/study_plan_repository.dart';
import '../repositories/study_task_repository.dart';

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

  // ── Per-plan, per-day study notifications ──────────────────────────────────
  //
  // Two notifications per remaining day of a plan:
  //  - an "upcoming" one at the plan's own reminder time, naming that day's
  //    actual tasks (not a generic ping)
  //  - a "missed" check-in later the same day, cancelled the instant the
  //    user finishes that day's tasks in-app (see cancelDayMissedCheck)
  // plus one immediate congratulations notification when a plan's last
  // task is completed.

  static const int _missedCheckHour = 20;
  static const int _missedCheckMinute = 30;

  int _dayUpcomingId(String dayId) => 5000 + dayId.hashCode.abs() % 4000;
  int _dayMissedId(String dayId) => 10000 + dayId.hashCode.abs() % 4000;
  int _planCompletedId(String planId) => 15000 + planId.hashCode.abs() % 4000;

  /// Schedules the full notification set for a plan. Call after the plan,
  /// its days, and its tasks are all saved — and after cancelling any
  /// previous schedule for this plan (e.g. on edit).
  Future<void> scheduleStudyPlanNotifications({
    required StudyPlan plan,
    required List<StudyDay> days,
    required List<StudyTask> tasks,
  }) async {
    if (!_initialized || kIsWeb || !plan.hasReminder) return;

    final tasksByDay = <String, List<StudyTask>>{};
    for (final t in tasks) {
      tasksByDay.putIfAbsent(t.dayId, () => []).add(t);
    }

    final nowTz = tz.TZDateTime.now(tz.local);

    for (final day in days) {
      if (day.isPast || day.isCompleted) continue;
      final dayTasks = tasksByDay[day.id] ?? const <StudyTask>[];
      if (dayTasks.isEmpty) continue;

      final date = day.date;
      final preview = dayTasks.length == 1
          ? dayTasks.first.title
          : '${dayTasks.first.title} + ${dayTasks.length - 1} more';

      final reminderAt = tz.TZDateTime(tz.local, date.year, date.month,
          date.day, plan.reminderHour!, plan.reminderMinute!);
      if (reminderAt.isAfter(nowTz)) {
        await _plugin.zonedSchedule(
          _dayUpcomingId(day.id),
          "Today's plan: ${plan.name} 📚",
          preview,
          reminderAt,
          _details(_chReminder, Importance.defaultImportance),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'study_plan:${plan.id}',
        );
      }

      final missedAt = tz.TZDateTime(tz.local, date.year, date.month,
          date.day, _missedCheckHour, _missedCheckMinute);
      if (missedAt.isAfter(nowTz)) {
        await _plugin.zonedSchedule(
          _dayMissedId(day.id),
          "Don't break your streak! ⏰",
          '${dayTasks.length} task${dayTasks.length == 1 ? '' : 's'} left in "${plan.name}" today',
          missedAt,
          _details(_chReminder, Importance.defaultImportance),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'study_plan:${plan.id}',
        );
      }
    }
  }

  /// Cancels every scheduled notification for a plan's days — call on
  /// delete, or right before rescheduling on edit.
  Future<void> cancelStudyPlanNotifications(List<StudyDay> days) async {
    if (!_initialized || kIsWeb) return;
    for (final day in days) {
      await _plugin.cancel(_dayUpcomingId(day.id));
      await _plugin.cancel(_dayMissedId(day.id));
    }
  }

  /// Cancels just one day's end-of-day "tasks left" check-in — call the
  /// moment that day's tasks all become complete so the reminder doesn't
  /// fire for something already finished.
  Future<void> cancelDayMissedCheck(String dayId) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.cancel(_dayMissedId(dayId));
  }

  /// Immediate (not scheduled) congratulations when a plan's last task is
  /// completed.
  Future<void> showStudyPlanCompleted({
    required String planId,
    required String planName,
  }) async {
    if (!_initialized || kIsWeb) return;
    await _plugin.show(
      _planCompletedId(planId),
      'Plan complete! 🎉',
      'You finished every task in "$planName" — best wishes for the exam!',
      _details(_chReminder, Importance.high),
      payload: 'saved_outputs',
    );
  }

  /// Re-derives and re-schedules every active plan's day notifications from
  /// scratch. Android AlarmManager entries don't survive a device reboot
  /// (RECEIVE_BOOT_COMPLETED alone doesn't re-register them for this
  /// plugin), so this runs once on every app launch as a cheap safety net —
  /// re-scheduling with the same deterministic IDs just overwrites whatever
  /// was there.
  Future<void> rescheduleAllActiveStudyPlans() async {
    if (!_initialized || kIsWeb) return;
    final plans = await StudyPlanRepository().getAll();
    final dayRepo = StudyDayRepository();
    final taskRepo = StudyTaskRepository();
    for (final plan in plans) {
      if (!plan.isActive || !plan.hasReminder) continue;
      final days = await dayRepo.getByPlan(plan.id);
      final tasks = await taskRepo.getByPlan(plan.id);
      await scheduleStudyPlanNotifications(
          plan: plan, days: days, tasks: tasks);
    }
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
