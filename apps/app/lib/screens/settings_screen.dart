import 'dart:io';

import 'package:flutter/material.dart';

import '../constants/app_languages.dart';
import '../database/database_helper.dart';
import '../repositories/settings_repository.dart';
import '../repositories/usage_log_repository.dart';
import '../services/auth_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/connectivity_service.dart';
import '../services/exam_sync_service.dart';
import '../services/notification_service.dart';
import '../services/study_plan_sync_service.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_feedback.dart';
import '../widgets/language_picker_sheet.dart';
import 'login_screen.dart';
import 'plans_screen.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settingsRepo = SettingsRepository();
  final _usageRepo = UsageLogRepository();

  final _inputPriceCtrl = TextEditingController();
  final _outputPriceCtrl = TextEditingController();
  final _tokenLimitCtrl = TextEditingController();

  String _language = 'English';
  String _gradeLevel = 'Grade 10';
  String _tone = 'normal';
  String _outputLength = 'medium';
  String _reasoningLevel = 'mid';
  String _themeMode = 'system';
  double _speechRate = 0.5;

  bool _loading = true;
  bool _syncing = false;
  Map<String, dynamic> _usage = {};

  bool _notifyOnComplete = true;
  bool _notifyOnQueueProcessed = true;
  bool _dailyReminderEnabled = false;
  int _reminderHour = 8;
  int _reminderMinute = 0;

  static const _grades = [
    'Grade 1',
    'Grade 2',
    'Grade 3',
    'Grade 4',
    'Grade 5',
    'Grade 6',
    'Grade 7',
    'Grade 8',
    'Grade 9',
    'Grade 10',
    'Grade 11',
    'Grade 12',
    'University',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _settingsRepo.getAll();
    final usage = await _usageRepo.getSummary();
    if (!mounted) return;

    setState(() {
      _language = all[SettingKeys.defaultLanguage] ?? 'English';
      _gradeLevel = all[SettingKeys.defaultGradeLevel] ?? 'Grade 10';
      _tone = all[SettingKeys.defaultTone] ?? 'normal';
      _outputLength = all[SettingKeys.defaultOutputLength] ?? 'medium';
      _reasoningLevel = all[SettingKeys.defaultReasoningLevel] ?? 'mid';
      _themeMode = all[SettingKeys.themeMode] ?? 'system';
      _speechRate = TtsService.instance.speechRate;
      _inputPriceCtrl.text = all[SettingKeys.inputTokenPrice] ?? '0.0005';
      _outputPriceCtrl.text = all[SettingKeys.outputTokenPrice] ?? '0.0015';
      _tokenLimitCtrl.text = all[SettingKeys.chatDailyTokenLimit] ?? '0';
      _notifyOnComplete =
          (all[SettingKeys.notifyOnComplete] ?? 'true') == 'true';
      _notifyOnQueueProcessed =
          (all[SettingKeys.notifyOnQueueProcessed] ?? 'true') == 'true';
      _dailyReminderEnabled = all[SettingKeys.dailyReminderEnabled] == 'true';
      _reminderHour =
          int.tryParse(all[SettingKeys.dailyReminderHour] ?? '8') ?? 8;
      _reminderMinute =
          int.tryParse(all[SettingKeys.dailyReminderMinute] ?? '0') ?? 0;
      _usage = usage;
      _loading = false;
    });
  }

  Future<void> _save(String key, String value) => _settingsRepo.set(key, value);

  void _changeTheme(String value) {
    setState(() => _themeMode = value);
    _save(SettingKeys.themeMode, value);
    themeNotifier.setFromString(value);
  }

  Future<void> _setDailyReminder(bool enabled) async {
    setState(() => _dailyReminderEnabled = enabled);
    await _save(SettingKeys.dailyReminderEnabled, enabled.toString());

    if (!enabled) {
      await NotificationService.instance.cancelDailyReminder();
      return;
    }

    final granted = await NotificationService.instance.requestPermission();
    if (!granted) {
      setState(() => _dailyReminderEnabled = false);
      await _save(SettingKeys.dailyReminderEnabled, 'false');
      if (mounted) {
        AppFeedback.showToast(context, 'Notification permission denied');
      }
      return;
    }

    await NotificationService.instance.scheduleDailyReminder(
      hour: _reminderHour,
      minute: _reminderMinute,
    );
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _reminderHour, minute: _reminderMinute),
    );
    if (picked == null) return;

    setState(() {
      _reminderHour = picked.hour;
      _reminderMinute = picked.minute;
    });
    await _save(SettingKeys.dailyReminderHour, picked.hour.toString());
    await _save(SettingKeys.dailyReminderMinute, picked.minute.toString());

    if (_dailyReminderEnabled) {
      await NotificationService.instance.scheduleDailyReminder(
        hour: picked.hour,
        minute: picked.minute,
      );
    }
  }

  Future<void> _syncNow() async {
    if (!ConnectivityService.instance.isOnline) {
      AppFeedback.showToast(context, 'You are offline');
      return;
    }
    setState(() => _syncing = true);
    try {
      await Future.wait([
        CatalogSyncService.instance.syncInBackground(),
        ExamSyncService.instance.pullMissing(),
        StudyPlanSyncService.instance.pullMissing(),
      ]);
      if (mounted) AppFeedback.showSuccessToast(context, 'Synced');
    } catch (_) {
      if (mounted) AppFeedback.showErrorToast(context, 'Sync failed — try again shortly');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _clearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This deletes all subjects, chapters, chunks, and saved outputs. Settings are kept and this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await DatabaseHelper.instance.clearAllData();
    if (mounted) {
      AppFeedback.showToast(context, 'All data cleared');
    }
  }

  /// The profile photo is never uploaded server-side, so it's the one
  /// piece of account-identifying data left on-device after logout —
  /// clear it so a different account signing in on the same device
  /// doesn't inherit the previous user's photo.
  Future<void> _clearLocalAvatar() async {
    try {
      final path = await _settingsRepo.get(SettingKeys.profileAvatarPath);
      if (path == null) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
      await _settingsRepo.set(SettingKeys.profileAvatarPath, '');
    } catch (_) {
      // Best-effort cleanup — never block logout on this.
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('You\'ll need to sign in again to use RightAnswer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.instance.logout();
    await _clearLocalAvatar();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 60),
        children: [
          _sectionTitle('Defaults', Icons.tune_outlined, theme),
          _card(
            theme,
            children: [
              _languagePickerRow(theme),
              const SizedBox(height: 14),
              _dropdownRow('Grade / Class', _gradeLevel, _grades, (value) {
                setState(() => _gradeLevel = value!);
                _save(SettingKeys.defaultGradeLevel, value!);
              }, theme),
              const SizedBox(height: 14),
              _dropdownRow('Tone', _tone, ['simple', 'normal', 'detailed'], (
                value,
              ) {
                setState(() => _tone = value!);
                _save(SettingKeys.defaultTone, value!);
              }, theme),
              const SizedBox(height: 14),
              _dropdownRow(
                'Output Length',
                _outputLength,
                ['short', 'medium', 'long'],
                (value) {
                  setState(() => _outputLength = value!);
                  _save(SettingKeys.defaultOutputLength, value!);
                },
                theme,
              ),
              const SizedBox(height: 14),
              _dropdownRow('Reasoning Depth', _reasoningLevel, [
                'low',
                'mid',
                'high',
              ], (value) {
                setState(() => _reasoningLevel = value!);
                _save(SettingKeys.defaultReasoningLevel, value!);
              }, theme),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Appearance', Icons.palette_outlined, theme),
          _card(
            theme,
            children: [
              Row(
                children: [
                  Text('Theme', style: _labelStyle(theme)),
                  const Spacer(),
                  _themeToggle(theme),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Voice & Reading', Icons.record_voice_over_outlined, theme),
          _card(
            theme,
            children: [
              Row(
                children: [
                  Text('Reading speed', style: _labelStyle(theme)),
                  const Spacer(),
                  Text(
                    '${_speechRate.toStringAsFixed(2)}x',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _speechRate,
                min: 0.25,
                max: 1.0,
                divisions: 15,
                label: '${_speechRate.toStringAsFixed(2)}x',
                onChanged: (value) => setState(() => _speechRate = value),
                onChangeEnd: (value) =>
                    TtsService.instance.setSpeechRate(value),
              ),
              Text(
                'Controls how fast "Read" speaks chat answers aloud.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Notifications', Icons.notifications_outlined, theme),
          _card(
            theme,
            children: [
              _switchTile(
                label: 'Notify when generation completes',
                value: _notifyOnComplete,
                onChanged: (value) async {
                  setState(() => _notifyOnComplete = value);
                  await _save(SettingKeys.notifyOnComplete, value.toString());
                  if (value) {
                    await NotificationService.instance.requestPermission();
                  }
                },
                theme: theme,
              ),
              Divider(color: theme.dividerColor, height: 1),
              _switchTile(
                label: 'Notify when queue is processed',
                value: _notifyOnQueueProcessed,
                onChanged: (value) async {
                  setState(() => _notifyOnQueueProcessed = value);
                  await _save(
                    SettingKeys.notifyOnQueueProcessed,
                    value.toString(),
                  );
                  if (value) {
                    await NotificationService.instance.requestPermission();
                  }
                },
                theme: theme,
              ),
              Divider(color: theme.dividerColor, height: 1),
              _switchTile(
                label: 'Daily study reminder',
                value: _dailyReminderEnabled,
                onChanged: _setDailyReminder,
                theme: theme,
              ),
              if (_dailyReminderEnabled) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: _pickReminderTime,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('Reminder time', style: _labelStyle(theme)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_reminderHour.toString().padLeft(2, '0')}:${_reminderMinute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Chat Limits', Icons.speed_outlined, theme),
          _card(
            theme,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daily Output Token Limit',
                          style: _labelStyle(theme),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Set 0 for unlimited. Chat stops when the limit is reached.',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _tokenLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'tokens',
                        isDense: true,
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (v) {
                        // Never negative — a negative limit would silently
                        // block all chat, since usage >= limit always holds.
                        final n = (int.tryParse(v.trim()) ?? 0).clamp(0, 1 << 30);
                        _save(SettingKeys.chatDailyTokenLimit, n.toString());
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('Usage & Pricing', Icons.bar_chart_outlined, theme),
          _card(
            theme,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: r'$ / 1K input tokens',
                        isDense: true,
                      ),
                      onSubmitted: (value) =>
                          _save(SettingKeys.inputTokenPrice, value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _outputPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: r'$ / 1K output tokens',
                        isDense: true,
                      ),
                      onSubmitted: (value) =>
                          _save(SettingKeys.outputTokenPrice, value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: theme.dividerColor),
              const SizedBox(height: 10),
              _usageGrid(theme),
            ],
          ),
          if (AuthService.instance.isLoggedIn) ...[
            const SizedBox(height: 20),
            _sectionTitle('Plan', Icons.workspace_premium_outlined, theme),
            _card(
              theme,
              children: [
                _actionTile(
                  icon: Icons.workspace_premium_outlined,
                  color: theme.colorScheme.primary,
                  label: _planDisplayName(
                    AuthService.instance.currentUser?.plan ?? 'hobby',
                  ),
                  subtitle: 'View plans, usage, and upgrade options',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PlansScreen()),
                  ),
                  theme: theme,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('Account', Icons.person_outline, theme),
            _card(
              theme,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        (AuthService.instance.currentUser?.name.isNotEmpty ==
                                true
                            ? AuthService.instance.currentUser!.name[0]
                            : AuthService.instance.currentUser?.email[0] ??
                                '?').toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AuthService.instance.currentUser?.name.isNotEmpty ==
                                    true
                                ? AuthService.instance.currentUser!.name
                                : 'Signed in',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            AuthService.instance.currentUser?.email ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Divider(color: theme.dividerColor, height: 24),
                _actionTile(
                  icon: Icons.person_outline,
                  color: theme.colorScheme.primary,
                  label: 'Edit Profile',
                  subtitle: 'Name, photo, and password',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                  theme: theme,
                ),
                Divider(color: theme.dividerColor, height: 1),
                _actionTile(
                  icon: Icons.logout_rounded,
                  color: Colors.red,
                  label: 'Log Out',
                  subtitle: 'Sign out of this account',
                  onTap: _logout,
                  theme: theme,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          if (AuthService.instance.isLoggedIn) ...[
            _sectionTitle('Cloud Sync', Icons.cloud_sync_outlined, theme),
            _card(
              theme,
              children: [
                Row(
                  children: [
                    Icon(
                      ConnectivityService.instance.isOnline
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_off_outlined,
                      size: 18,
                      color: ConnectivityService.instance.isOnline
                          ? const Color(0xFF059669)
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ConnectivityService.instance.isOnline
                            ? 'Chats, exams, and study plans sync automatically'
                            : 'Offline — changes will sync once reconnected',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.65,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _syncing ? null : _syncNow,
                    icon: _syncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          _sectionTitle('Data', Icons.storage_outlined, theme),
          _card(
            theme,
            children: [
              _actionTile(
                icon: Icons.delete_forever_outlined,
                color: Colors.red,
                label: 'Clear All Local Data',
                subtitle:
                    'Removes subjects, chapters, chunks, and saved outputs',
                onTap: _clearData,
                theme: theme,
              ),
              Divider(color: theme.dividerColor, height: 1),
              _actionTile(
                icon: Icons.upload_file_outlined,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                label: 'Export Data',
                subtitle: 'Coming soon',
                onTap: () =>
                    AppFeedback.showToast(context, 'Export coming soon'),
                theme: theme,
              ),
              Divider(color: theme.dividerColor, height: 1),
              _actionTile(
                icon: Icons.download_outlined,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                label: 'Import Data',
                subtitle: 'Coming soon',
                onTap: () =>
                    AppFeedback.showToast(context, 'Import coming soon'),
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle('About', Icons.info_outline, theme),
          _card(
            theme,
            children: [
              Row(
                children: [
                  Text('App', style: _labelStyle(theme)),
                  const Spacer(),
                  Text(
                    'RightAnswer',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Version', style: _labelStyle(theme)),
                  const Spacer(),
                  Text(
                    '1.0.0',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeToggle(ThemeData theme) {
    final options = [
      ('system', Icons.brightness_auto_outlined, 'Auto'),
      ('light', Icons.light_mode_outlined, 'Light'),
      ('dark', Icons.dark_mode_outlined, 'Dark'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final selected = _themeMode == option.$1;
          return GestureDetector(
            onTap: () => _changeTheme(option.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    option.$2,
                    size: 15,
                    color: selected
                        ? Colors.white
                        : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    option.$3,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? Colors.white
                          : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _usageGrid(ThemeData theme) {
    final stats = [
      ('Today - Tokens In', '${_usage['todayInputTokens']}'),
      ('Today - Tokens Out', '${_usage['todayOutputTokens']}'),
      (
        'Today - Cost',
        '\$${(_usage['todayCost'] as double).toStringAsFixed(5)}',
      ),
      ('All Time - Tokens In', '${_usage['allInputTokens']}'),
      ('All Time - Tokens Out', '${_usage['allOutputTokens']}'),
      (
        'All Time - Cost',
        '\$${(_usage['allCost'] as double).toStringAsFixed(4)}',
      ),
    ];

    return Column(
      children: stats
          .map(
            (stat) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Text(
                    stat.$1,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.65,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    stat.$2,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _sectionTitle(String text, IconData icon, ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
            letterSpacing: 0.6,
          ),
        ),
      ],
    ),
  );

  Widget _card(ThemeData theme, {required List<Widget> children}) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: theme.dividerColor),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _switchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ThemeData theme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _dropdownRow(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
    ThemeData theme,
  ) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label, style: _labelStyle(theme))),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: options.contains(value) ? value : options.first,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
            items: options
                .map(
                  (option) => DropdownMenuItem(
                    value: option,
                    child: Text(option, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _languagePickerRow(ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text('Language', style: _labelStyle(theme)),
        ),
        Expanded(
          child: InkWell(
            onTap: () async {
              final selected = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => LanguagePickerSheet(
                  title: 'Select Language',
                  languages: appLanguageLabels,
                  selectedLanguage: _language,
                ),
              );
              if (selected == null || !mounted) return;
              setState(() => _language = selected);
              await _save(SettingKeys.defaultLanguage, selected);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _language,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  String _planDisplayName(String plan) => switch (plan) {
    'pro' => 'Pro Plan',
    'scholar' => 'Scholar Plan',
    _ => 'Hobby Plan (Free)',
  };

  TextStyle _labelStyle(ThemeData theme) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
  );

  @override
  void dispose() {
    _inputPriceCtrl.dispose();
    _outputPriceCtrl.dispose();
    _tokenLimitCtrl.dispose();
    super.dispose();
  }
}
