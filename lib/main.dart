import 'package:flutter/material.dart';
import 'repositories/settings_repository.dart';
import 'screens/home_screen.dart';
import 'screens/saved_outputs_screen.dart';
import 'screens/queue_screen.dart';
import 'services/background_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/queue_service.dart';
import 'theme/app_theme.dart';

/// Global navigator key — used by [NotificationService] for tap navigation.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Load persisted theme before first paint ───────────────────────────────
  final savedTheme = await SettingsRepository().get(SettingKeys.themeMode);
  if (savedTheme != null) themeNotifier.setFromString(savedTheme);

  // ── Notifications ─────────────────────────────────────────────────────────
  await NotificationService.instance.initialize();
  NotificationService.onTap = _handleNotificationTap;

  // ── Background workmanager ────────────────────────────────────────────────
  await BackgroundService.initialize();
  await BackgroundService.registerPeriodicQueueCheck();

  // ── Queue service ─────────────────────────────────────────────────────────
  await QueueService.instance.initialize();

  // ── Connectivity: trigger queue processing when back online ───────────────
  ConnectivityService.instance.onReconnect(() async {
    final pending = await QueueService.instance.getAll()
        .then((list) => list.where((r) => r.status == 'pending').length);
    if (pending > 0) {
      await NotificationService.instance.showConnectivityRestored(pending);
    }
    await QueueService.instance.processQueue();
  });
  await ConnectivityService.instance.initialize();

  // ── Reschedule daily reminder if enabled ──────────────────────────────────
  final settings = await SettingsRepository().getAll();
  if (settings[SettingKeys.dailyReminderEnabled] == 'true') {
    final hour = int.tryParse(settings[SettingKeys.dailyReminderHour] ?? '') ?? 8;
    final min  = int.tryParse(settings[SettingKeys.dailyReminderMinute] ?? '') ?? 0;
    await NotificationService.instance.scheduleDailyReminder(hour: hour, minute: min);
  }

  runApp(const RightAnswerApp());
}

void _handleNotificationTap(String? payload) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  switch (payload) {
    case 'saved_outputs':
      nav.push(MaterialPageRoute(builder: (_) => const SavedOutputsScreen()));
    case 'queue':
      nav.push(MaterialPageRoute(builder: (_) => const QueueScreen()));
    default:
      nav.popUntil((r) => r.isFirst);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class RightAnswerApp extends StatefulWidget {
  const RightAnswerApp({super.key});

  @override
  State<RightAnswerApp> createState() => _RightAnswerAppState();
}

class _RightAnswerAppState extends State<RightAnswerApp> {
  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(_onTheme);
  }

  void _onTheme() => setState(() {});

  @override
  void dispose() {
    themeNotifier.removeListener(_onTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RightAnswer',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: themeNotifier.mode,
      home: const HomeScreen(),
    );
  }
}
