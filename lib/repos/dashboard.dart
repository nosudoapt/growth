import 'dart:convert';

import '../core/db.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/dashboard.dart';
import '../repos/prompts.dart';
import 'llm.dart';
import 'library.dart';
import 'checkins.dart';

/// Stores the last good dashboard. On LLM validation failure (after one
/// accurate retry it still fails), keeps serving the previous version.
class DashboardRepo {
  const DashboardRepo._();

  static Future<DashboardData?> current() async {
    final db = await Db.instance();
    final rows = await db.query('dashboards', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    try {
      final raw = jsonDecode(r['json'] as String) as Map<String, dynamic>;
      return DashboardData.fromValidated(
          raw, DateTime.tryParse(r['updated_at'] as String) ?? DateTime.now());
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastUpdated() async {
    final rows =
        await (await Db.instance()).query('dashboards', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['updated_at'] as String);
  }

  /// Rebuild validation + retry pipeline. Returns the new data, or null when
  /// the model output failed twice and the last good result stays in place.
  static Future<DashboardData?> rebuild({
    required LlmService llm,
    required LlmConfig config,
    required String profileText,
    required bool weekly,
  }) async {
    final checkins = await CheckinRepo.lastNights(7);
    final minutes = await LibraryRepo.minutesByDay(days: 7);
    final liked = await recentLikes();
    final skipped = await recentSkips();

    final checkinsJson = [
      for (final c in checkins) jsonEncode(c),
    ];

    final system = Prompts.dashboardVersion;
    final prompt = Prompts.dashboard(
      profileText: profileText,
      last7CheckinsJson: checkinsJson,
      minutesByDay: minutes,
      likedTitles: liked,
      skippedTitles: skipped,
      weeklyRebuild: weekly,
    );

    try {
      final raw = await llm.complete<String>(
        config: config,
        system: system,
        prompt: prompt,
        parse: (t) {
          final obj = extractJsonObject(t);
          final errs = validateDashboard(obj);
          if (errs.isNotEmpty) {
            throw const FormatException('schema');
          }
          return jsonEncode(obj);
        },
        maxOutputTokens: 1800,
      );
      final saved = await saveGood(raw);
      return saved;
    } on SpendBlocked {
      rethrow;
    } catch (_) {
      // Second (last) attempt: one retry with a nudge to strictly match.
      try {
        final raw = await llm.complete<String>(
          config: config,
          system: '$system\nYour previous reply failed schema validation. Follow the schema exactly.',
          prompt: prompt,
          parse: (t) {
            final obj = extractJsonObject(t);
            final errs = validateDashboard(obj);
            if (errs.isNotEmpty) throw const FormatException('schema');
            return jsonEncode(obj);
          },
          maxOutputTokens: 1800,
        );
        return await saveGood(raw);
      } on SpendBlocked {
        rethrow;
      } catch (_) {
        return null; // fall back to last good result (already stored)
      }
    }
  }

  static Future<DashboardData?> saveGood(String jsonEncoded) async {
    final db = await Db.instance();
    final obj = jsonDecode(jsonEncoded) as Map<String, dynamic>;
    final data =
        DashboardData.fromValidated(obj, DateTime.now());
    await db.insert(
      'dashboards',
      {
        'id': 1,
        'json': jsonEncode(obj),
        'updated_at': DateTime.now().toIso8601String(),
        'is_good': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return data;
  }

  static Future<List<String>> recentLikes() async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        'SELECT item_key FROM interactions WHERE kind = \'like\' '
        'AND ts > ? ORDER BY ts DESC LIMIT 50',
        [DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch]);
    return [for (final r in rows) r['item_key'] as String];
  }

  static Future<List<String>> recentSkips() async {
    final db = await Db.instance();
    final rows = await db.rawQuery(
        'SELECT item_key FROM interactions WHERE kind = \'skip\' '
        'AND ts > ? ORDER BY ts DESC LIMIT 50',
        [DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch]);
    return [for (final r in rows) r['item_key'] as String];
  }
}
