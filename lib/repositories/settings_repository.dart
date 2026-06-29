import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class SettingsRepository {
  final _db = DatabaseHelper.instance;

  Future<String?> get(String key) async {
    final db = await _db.database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> set(String key, String value) async {
    final db = await _db.database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(String key) async {
    final db = await _db.database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<Map<String, String>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }
}

// Well-known setting keys
class SettingKeys {
  static const String openAiApiKey = 'openai_api_key';
  static const String defaultLanguage = 'default_language';
  static const String defaultGradeLevel = 'default_grade_level';
  static const String defaultTone = 'default_tone';
  static const String defaultOutputLength = 'default_output_length';
  static const String themeMode = 'theme_mode';
  static const String accentColor = 'accent_color';
  static const String inputTokenPrice = 'input_token_price';
  static const String outputTokenPrice = 'output_token_price';
  static const String openAiModel = 'openai_model';
  // Notifications
  static const String notifyOnComplete = 'notify_on_complete';
  static const String notifyOnQueueProcessed = 'notify_on_queue_processed';
  static const String dailyReminderEnabled = 'daily_reminder_enabled';
  static const String dailyReminderHour = 'daily_reminder_hour';
  static const String dailyReminderMinute = 'daily_reminder_minute';
}
