import '../database/database_helper.dart';
import '../models/usage_log.dart';

class UsageLogRepository {
  final _db = DatabaseHelper.instance;

  Future<void> insert(UsageLog log) async {
    final db = await _db.database;
    await db.insert('usage_logs', log.toMap());
  }

  Future<List<UsageLog>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('usage_logs', orderBy: 'createdAt DESC');
    return rows.map(UsageLog.fromMap).toList();
  }

  Future<Map<String, dynamic>> getSummary() async {
    final db = await _db.database;

    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day).toIso8601String();

    final allRows = await db.rawQuery(
        'SELECT SUM(inputTokensEstimate) as it, SUM(outputTokensEstimate) as ot, SUM(estimatedCost) as cost FROM usage_logs');
    final todayRows = await db.rawQuery(
        'SELECT SUM(inputTokensEstimate) as it, SUM(outputTokensEstimate) as ot, SUM(estimatedCost) as cost FROM usage_logs WHERE createdAt >= ?',
        [todayStart]);

    final all = allRows.first;
    final todayData = todayRows.first;

    return {
      'allInputTokens': (all['it'] as num?)?.toInt() ?? 0,
      'allOutputTokens': (all['ot'] as num?)?.toInt() ?? 0,
      'allCost': (all['cost'] as num?)?.toDouble() ?? 0.0,
      'todayInputTokens': (todayData['it'] as num?)?.toInt() ?? 0,
      'todayOutputTokens': (todayData['ot'] as num?)?.toInt() ?? 0,
      'todayCost': (todayData['cost'] as num?)?.toDouble() ?? 0.0,
    };
  }
}
