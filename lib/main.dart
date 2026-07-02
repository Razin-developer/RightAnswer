import 'package:flutter/material.dart';

import 'app/app_router.dart';
import 'repositories/settings_repository.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/saved_outputs_screen.dart';
import 'services/app_link_service.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/queue_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsRepo = SettingsRepository();
  await settingsRepo.delete(SettingKeys.openAiApiKey);

  final savedTheme = await settingsRepo.get(SettingKeys.themeMode);
  if (savedTheme != null) {
    themeNotifier.setFromString(savedTheme);
  }

  await NotificationService.instance.initialize();
  NotificationService.onTap = _handleNotificationTap;

  await BackgroundService.initialize();
  await BackgroundService.registerPeriodicQueueCheck();

  await QueueService.instance.initialize();

  await AuthService.instance.init();
  await AppLinkService.instance.initialize();

  ConnectivityService.instance.onReconnect(() async {
    final pending = await QueueService.instance.getAll().then(
      (list) => list.where((request) => request.status == 'pending').length,
    );
    if (pending > 0) {
      await NotificationService.instance.showConnectivityRestored(pending);
    }
    await QueueService.instance.processQueue();
  });
  await ConnectivityService.instance.initialize();

  final settings = await settingsRepo.getAll();
  if (settings[SettingKeys.dailyReminderEnabled] == 'true') {
    final hour =
        int.tryParse(settings[SettingKeys.dailyReminderHour] ?? '') ?? 8;
    final minute =
        int.tryParse(settings[SettingKeys.dailyReminderMinute] ?? '') ?? 0;
    await NotificationService.instance.scheduleDailyReminder(
      hour: hour,
      minute: minute,
    );
  }

  runApp(const RightAnswerApp());
}

void _handleNotificationTap(String? payload) {
  final navigator = navigatorKey.currentState;
  if (navigator == null) {
    return;
  }

  if (payload == 'saved_outputs') {
    navigator.push(
      MaterialPageRoute(builder: (_) => const SavedOutputsScreen()),
    );
  } else if (payload == 'queue') {
    navigator.push(MaterialPageRoute(builder: (_) => const QueueScreen()));
  } else {
    navigator.popUntil((route) => route.isFirst);
  }
}

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
    AppLinkService.instance.dispose();
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
      home: AuthService.instance.isLoggedIn
          ? const MainScreen()
          : const LoginScreen(),
    );
  }
}
