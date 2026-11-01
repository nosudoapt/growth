import 'dart:convert';

import '../logic/profile.dart';
import '../core/db.dart';

/// The local text profile (≤800 words), compiled from signals and rewritten
/// weekly. Stored as one row; regenerated offline, refined by the LLM.
class ProfileRepo {
  const ProfileRepo._();

  static Future<String> current() async {
    final db = await Db.instance();
    final rows = await db.query('profile', where: 'id = 1', limit: 1);
    if (rows.isNotEmpty) return rows.first['body'] as String;
    final text = compileProfile(
      goals: (await goals()),
      likedTopics: await likedTopics(),
      skippedTopics: await skippedTopics(),
      checkinThemes: [],
    );
    await save(text);
    return text;
  }

  static Future<List<String>> goals() async {
    final s = await Db.kvGet('goals');
    if (s == null || s.isEmpty) return kSeedGoals;
    try {
      final l = jsonDecode(s) as List;
      return l.whereType<String>().toList();
    } catch (_) {
      return kSeedGoals;
    }
  }

  static Future<void> setGoals(List<String> g) async {
    await Db.kvSet('goals', jsonEncode(g));
  }

  static Future<List<String>> likedTopics() async {
    final raw = await Db.kvGet('topic_weights');
    if (raw == null) return const [];
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final positive = m.entries
          .where((e) => (e.value as num?)! >= 2)
          .map((e) => e.key)
          .toList();
      positive.sort((a, b) =>
          ((m[b] as num?)!.toInt()).compareTo((m[a] as num?)!.toInt()));
      return positive;
    } catch (_) {
      return const [];
    }
  }

  static Future<List<String>> skippedTopics() async {
    final raw = await Db.kvGet('topic_weights');
    if (raw == null) return const [];
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.entries
          .where((e) => (e.value as num?)! <= -2)
          .map((e) => e.key)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(String body) async {
    final db = await Db.instance();
    await db.insert(
      'profile',
      {
        'id': 1,
        'body': body,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Recompile from signals (runs with the weekly rebuild; idempotent).
  static Future<void> refresh() async {
    final text = compileProfile(
      goals: await goals(),
      likedTopics: await likedTopics(),
      skippedTopics: await skippedTopics(),
      checkinThemes: await _themes(),
    );
    await save(text);
  }

  /// Most common words from recent answers — a quiet, local theme tracker.
  static Future<List<String>> _themes() async {
    final db = await Db.instance();
    final rows = await db.query('checkins',
        where: 'ts > ?',
        whereArgs: [
          DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch
        ],
        columns: ['answer']);
    final stop = {
      'the', 'and', 'was', 'with', 'that', 'for', 'you', 'what', 'have',
      'about', 'into', 'did', 'today', 'not', 'were', 'when', 'this', 'but',
    };
    final counts = <String, int>{};
    for (final r in rows) {
      for (final w in (r['answer'] as String).toLowerCase().split(RegExp(r'[^a-z]+'))) {
        if (w.length < 4 || stop.contains(w)) continue;
        counts[w] = (counts[w] ?? 0) + 1;
      }
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted.take(8).toList();
  }
}
