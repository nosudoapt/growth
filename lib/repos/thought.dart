import 'dart:convert';

import '../core/db.dart';
import '../logic/rotation.dart';
import '../seed/thoughts.dart';
import 'llm.dart';
import 'prompts.dart';

/// Thought of the day: generated once daily by the LLM from the profile.
/// Output longer than 2 sentences (or any failure) falls back to the bundled
/// bank, rotated without repeats for 30 days.
class ThoughtRepo {
  const ThoughtRepo._();

  /// Bundled-bank rotation: pick an index not used in the last 30 days.
  static Future<int> bankIndex({DateTime? today}) async {
    final db = await Db.instance();
    final now = today ?? DateTime.now();
    final rows = await db.query('thought_days', orderBy: 'date DESC');
    final recent = recentSince(
      [for (final r in rows) (r['date'] as String, r['thought_index'] as int)],
      30,
      now,
    );
    return Rotation.nextIndex(kThoughtBank.length, recent);
  }

  /// Resolve (and cache) today's thought. Works fully offline: bank first
  /// choice always exists; LLM replaces it only when it validates.
  static Future<String> today({
    LlmService? llm,
    String? profileText,
  }) async {
    final db = await Db.instance();
    final d = Db.today();
    final rows = await db
        .query('thought_days', where: 'date = ?', whereArgs: [d], limit: 1);
    if (rows.isNotEmpty) return rows.first['content'] as String;

    final idx = await bankIndex();
    final fallback = kThoughtBank[idx].text;
    var content = fallback;

    final svc = llm;
    final storedKey = await Db.kvGet('llm_config');
    if (svc != null && profileText != null && profileText.isNotEmpty && storedKey != null) {
      try {
        final config = await svc.loadConfig();
        content = await svc.complete<String>(
          config: config,
          system: Prompts.thoughtSystem(),
          prompt: Prompts.thoughtOfDay(profileText),
          maxOutputTokens: 200,
          parse: (t) {
            final s = t.trim().replaceAll('"', ' ');
            final sentences =
                RegExp(r'[.!?]').allMatches(s).length;
            final clean = (sentences == 0 ? 1 : sentences) <= 2;
            if (!clean) throw const FormatException('too long');
            return s;
          },
        );
      } catch (_) {
        content = fallback; // validation/rejection/network → bank
      }
    }

    await db.insert(
      'thought_days',
      {'date': d, 'thought_index': idx, 'content': content},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return content;
  }
}
