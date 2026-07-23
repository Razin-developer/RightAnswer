import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'app/app_router.dart';
import 'repositories/settings_repository.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/saved_outputs_screen.dart';
import 'services/app_link_service.dart';
import 'services/auth_service.dart';
import 'services/background_service.dart';
import 'services/catalog_sync_service.dart';
import 'services/connectivity_service.dart';
import 'services/exam_sync_service.dart';
import 'services/notification_service.dart';
import 'services/queue_service.dart';
import 'services/study_plan_sync_service.dart';
import 'theme/app_theme.dart';

/// Runs a bootstrap step without letting it block app startup. main() used
/// to be a flat chain of awaited calls — any single one throwing (a plugin
/// missing on an odd device/OS combo, a corrupted local DB row, a timed-out
/// platform channel) meant `runApp` never ran at all, i.e. the app failed
/// to even show a screen. Every step below is independently non-fatal: it
/// logs and moves on, so a broken notifications permission or background
/// task never takes the whole app down with it.
Future<void> _bootstrapStep(String label, Future<void> Function() step) async {
  try {
    await step();
  } catch (error, stack) {
    _logBootstrapFailure(label, error, stack);
  }
}

void _logBootstrapFailure(String label, Object error, StackTrace stack) {
  developer.log(
    'Bootstrap step failed: $label',
    name: 'main',
    error: error,
    stackTrace: stack,
    level: 900, // WARNING
  );
}

void main() async {
  // Catches anything that escapes Flutter's own error handling (errors
  // thrown from timers, futures, and platform channel callbacks outside
  // the widget build/layout/paint phases) so a stray uncaught exception
  // logs instead of crashing the isolate.
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // A widget that throws during build normally shows Flutter's red
      // error screen in debug and a blank grey box in release — replace
      // both with a small, branded fallback so a single broken screen
      // never looks like the whole app crashed.
      ErrorWidget.builder = (details) => _BootErrorFallback(details: details);

      // Framework-caught errors (build/layout/paint, gesture callbacks)
      // route here — log them instead of only the console dump, so they
      // survive into whatever crash-reporting hook gets added later.
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _logBootstrapFailure(
          'FlutterError (${details.library ?? 'unknown'})',
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };
      // Errors that escape both the widget framework and the zone below
      // (rare — mainly native platform callbacks) land here as a last
      // resort. Returning true marks them handled so the engine doesn't
      // additionally treat them as fatal.
      PlatformDispatcher.instance.onError = (error, stack) {
        _logBootstrapFailure('PlatformDispatcher', error, stack);
        return true;
      };

      final settingsRepo = SettingsRepository();
      await _bootstrapStep('theme', () async {
        final savedTheme = await settingsRepo.get(SettingKeys.themeMode);
        if (savedTheme != null) {
          themeNotifier.setFromString(savedTheme);
        }
      });

      await _bootstrapStep('notifications', () async {
        await NotificationService.instance.initialize();
        NotificationService.onTap = _handleNotificationTap;
      });

      await _bootstrapStep('background service', () async {
        await BackgroundService.initialize();
        await BackgroundService.registerPeriodicQueueCheck();
      });

      await _bootstrapStep(
        'queue service',
        QueueService.instance.initialize,
      );

      await _bootstrapStep(
        'connectivity',
        ConnectivityService.instance.initialize,
      );
      await _bootstrapStep('auth', AuthService.instance.init);
      await _bootstrapStep(
        'app links',
        AppLinkService.instance.initialize,
      );

      // Best-effort: a throwing listener here would only affect the
      // reconnect-triggered queue flush, never app startup, so it's left
      // outside _bootstrapStep — but each async step inside still gets its
      // own guard so one failure (e.g. the notification) doesn't stop the
      // queue from being processed.
      ConnectivityService.instance.onReconnect(() async {
        try {
          final pending = await QueueService.instance.getAll().then(
            (list) =>
                list.where((request) => request.status == 'pending').length,
          );
          if (pending > 0) {
            await NotificationService.instance.showConnectivityRestored(
              pending,
            );
          }
        } catch (error, stack) {
          _logBootstrapFailure('reconnect notification', error, stack);
        }
        try {
          await QueueService.instance.processQueue();
        } catch (error, stack) {
          _logBootstrapFailure('reconnect queue flush', error, stack);
        }
      });

      await _bootstrapStep('daily reminder', () async {
        final settings = await settingsRepo.getAll();
        if (settings[SettingKeys.dailyReminderEnabled] == 'true') {
          final hour =
              int.tryParse(settings[SettingKeys.dailyReminderHour] ?? '') ??
              8;
          final minute =
              int.tryParse(settings[SettingKeys.dailyReminderMinute] ?? '') ??
              0;
          await NotificationService.instance.scheduleDailyReminder(
            hour: hour,
            minute: minute,
          );
        }
      });

      var seenOnboarding = false;
      await _bootstrapStep('onboarding flag', () async {
        seenOnboarding = await hasSeenOnboarding();
      });

      // Auth gate: if we're online and there's no valid session, the user
      // must log in. If we're offline, skip straight into the app in
      // restricted mode (local data only, AI generation blocked — see
      // AIBackendService). If we're online and already have a valid
      // session (AuthService.init() above already validated it against
      // /api/auth/me), skip straight to the app. Connectivity/auth
      // defaulting to false above (their _bootstrapStep failing) means
      // this conservatively falls back to "offline" rather than forcing a
      // login screen the user can't get past.
      final requiresLogin =
          ConnectivityService.instance.isOnline &&
          !AuthService.instance.isLoggedIn;

      runApp(
        RightAnswerApp(
          showOnboarding: !seenOnboarding,
          requiresLogin: requiresLogin,
        ),
      );

      // Low-priority background refresh of the subject/chapter catalog used
      // by the optional chapter picker (chat "+" menu, exam/study-plan
      // creation). Deliberately not awaited — must never delay first frame,
      // and silently no-ops when offline (retries on next launch). See
      // CatalogSyncService.
      unawaited(CatalogSyncService.instance.syncInBackground());
      // Same idea for exams/study plans — pulls anything that exists on
      // the server but not on this device (a reinstall, a new device)
      // without ever overwriting local data. See ExamSyncService /
      // StudyPlanSyncService.
      unawaited(ExamSyncService.instance.pullMissing());
      unawaited(StudyPlanSyncService.instance.pullMissing());
    },
    (error, stack) => _logBootstrapFailure('uncaught (zone)', error, stack),
  );
}

class _BootErrorFallback extends StatelessWidget {
  final FlutterErrorDetails details;
  const _BootErrorFallback({required this.details});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFFFF4F1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFCC785C),
            size: 28,
          ),
          const SizedBox(height: 8),
          const Text(
            'Something went wrong displaying this.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF6C6A64)),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 6),
            Text(
              details.exceptionAsString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6C6A64)),
            ),
          ],
        ],
      ),
    );
  }
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
  final bool showOnboarding;
  final bool requiresLogin;

  const RightAnswerApp({
    super.key,
    required this.showOnboarding,
    required this.requiresLogin,
  });

  @override
  State<RightAnswerApp> createState() => _RightAnswerAppState();
}

class _RightAnswerAppState extends State<RightAnswerApp> {
  late bool _showOnboarding = widget.showOnboarding;

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

  Widget _home() {
    if (_showOnboarding) {
      return OnboardingScreen(
        onDone: () => setState(() => _showOnboarding = false),
      );
    }
    if (widget.requiresLogin) {
      return const LoginScreen();
    }
    return const MainScreen();
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
      home: _home(),
    );
  }
}
